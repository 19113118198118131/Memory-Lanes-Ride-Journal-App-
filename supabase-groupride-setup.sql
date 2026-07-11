-- ============================================================
-- Memory Lanes: Group Rides — one-time setup
-- Run this in Supabase Dashboard -> SQL Editor -> New query
-- One route, one secret link, many riders on the same live map.
-- ============================================================

-- 1) A group ride ties ONE planned route to ONE secret invite token that
--    many riders share. Unlike route-copy sharing, everyone who joins rides
--    the same object, so all their live positions land on the same map.
create table if not exists group_rides (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references planned_routes(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  share_token uuid not null default gen_random_uuid(),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists group_rides_share_token_idx on group_rides (share_token);
create index if not exists group_rides_owner_idx on group_rides (owner_id);

alter table group_rides enable row level security;

create policy "owners select own group rides" on group_rides
  for select using (auth.uid() = owner_id);
create policy "owners insert own group rides" on group_rides
  for insert with check (auth.uid() = owner_id);
create policy "owners update own group rides" on group_rides
  for update using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "owners delete own group rides" on group_rides
  for delete using (auth.uid() = owner_id);

-- 2) Membership: who has joined. Rows are written by the join_group_ride
--    function (SECURITY DEFINER) — the token is the admission ticket.
create table if not exists group_ride_members (
  group_ride_id uuid not null references group_rides(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_ride_id, user_id)
);

alter table group_ride_members enable row level security;

create policy "members select own membership" on group_ride_members
  for select using (auth.uid() = user_id);
create policy "members delete own membership" on group_ride_members
  for delete using (auth.uid() = user_id);

-- 3) Live positions can now belong to a group ride.
alter table live_positions add column if not exists group_ride_id uuid references group_rides(id) on delete cascade;
create index if not exists live_positions_group_ride_idx on live_positions (group_ride_id);

-- 4) Read a group ride by its token (anon OK — the token is the key).
--    Includes the underlying route geometry, the host's display name,
--    member count, and is_owner/is_member flags for the caller.
create or replace function get_group_ride(token uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', g.id,
    'title', g.title,
    'is_active', g.is_active,
    'created_at', g.created_at,
    'hosted_by', nullif(trim(coalesce(p.display_name, '')), ''),
    'member_count', (select count(*) from group_ride_members m where m.group_ride_id = g.id),
    'is_owner', (auth.uid() is not null and auth.uid() = g.owner_id),
    'is_member', (auth.uid() is not null and exists (
       select 1 from group_ride_members m where m.group_ride_id = g.id and m.user_id = auth.uid())),
    'route_id', r.id,
    'route_title', r.title,
    'distance_km', r.distance_km,
    'elevation_m', r.elevation_m,
    'route', r.route
  )
  from group_rides g
  join planned_routes r on r.id = g.route_id
  left join profiles p on p.user_id = g.owner_id
  where g.share_token = token
    and g.is_active = true
  limit 1;
$$;

revoke all on function get_group_ride(uuid) from public;
grant execute on function get_group_ride(uuid) to anon, authenticated;

-- 5) Join a group ride (authenticated only). The token admits you; the
--    membership row is what your live position hangs off. Returns the same
--    payload as get_group_ride so the ride tracker can start immediately.
create or replace function join_group_ride(token uuid)
returns jsonb
language plpgsql
security definer
volatile
set search_path = public
as $$
declare
  gid uuid;
begin
  if auth.uid() is null then
    return null;
  end if;
  select g.id into gid from group_rides g
    where g.share_token = token and g.is_active = true limit 1;
  if gid is null then
    return null;
  end if;
  insert into group_ride_members (group_ride_id, user_id)
    values (gid, auth.uid())
    on conflict do nothing;
  return get_group_ride(token);
end;
$$;

revoke all on function join_group_ride(uuid) from public;
grant execute on function join_group_ride(uuid) to authenticated;

-- 6) Live riders on a group ride. Same freshness window as shared routes
--    (5 min). Authenticated callers don't get their own row back — the ride
--    tracker already draws the rider's own position locally.
create or replace function get_group_live_riders(token uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    jsonb_agg(jsonb_build_object(
      'name', coalesce(nullif(trim(coalesce(p.display_name, '')), ''), 'A rider'),
      'lat', lp.lat,
      'lng', lp.lng,
      'speed_kmh', lp.speed_kmh,
      'updated_at', lp.updated_at
    ) order by lp.updated_at desc),
    '[]'::jsonb
  )
  from group_rides g
  join live_positions lp on lp.group_ride_id = g.id
  left join profiles p on p.user_id = lp.user_id
  where g.share_token = token
    and g.is_active = true
    and lp.updated_at > now() - interval '5 minutes'
    and (auth.uid() is null or lp.user_id <> auth.uid());
$$;

revoke all on function get_group_live_riders(uuid) from public;
grant execute on function get_group_live_riders(uuid) to anon, authenticated;
