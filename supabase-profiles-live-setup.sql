-- ============================================================
-- Memory Lanes: Rider Profiles + Live Riders on Shared Routes
-- Run this in Supabase Dashboard -> SQL Editor -> New query
-- ============================================================

-- 1) Rider profiles: a display name + region shown on shared-route invite
--    pages ("Shared by Samar"). Owner-only via RLS; other users only ever
--    see the display name, and only through the SECURITY DEFINER functions
--    below — the table itself is never publicly readable.
create table if not exists profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  region text not null default '',
  updated_at timestamptz not null default now()
);

alter table profiles enable row level security;

create policy "owners select own profile" on profiles
  for select using (auth.uid() = user_id);
create policy "owners insert own profile" on profiles
  for insert with check (auth.uid() = user_id);
create policy "owners update own profile" on profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 2) Live positions: one row per rider, upserted while they ride a shared
--    route WITH live-broadcast switched on (off by default — the rider must
--    opt in every ride). Owner-only via RLS; viewers only ever read through
--    get_live_riders(token), which requires holding the route's secret
--    invite link. Positions older than 5 minutes are treated as gone, so a
--    crashed browser can't leave a rider "live" forever.
create table if not exists live_positions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  route_id uuid not null references planned_routes(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  speed_kmh double precision,
  updated_at timestamptz not null default now()
);

create index if not exists live_positions_route_id_idx on live_positions (route_id);

alter table live_positions enable row level security;

create policy "owners select own live position" on live_positions
  for select using (auth.uid() = user_id);
create policy "owners insert own live position" on live_positions
  for insert with check (auth.uid() = user_id);
create policy "owners update own live position" on live_positions
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "owners delete own live position" on live_positions
  for delete using (auth.uid() = user_id);

-- 3) Extend get_shared_route to attribute the route to its owner's chosen
--    display name (and nothing else — user_id stays stripped).
create or replace function get_shared_route(token uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select (to_jsonb(r.*) - 'user_id')
         || jsonb_build_object(
              'shared_by', nullif(trim(coalesce(p.display_name, '')), ''),
              'shared_by_region', nullif(trim(coalesce(p.region, '')), '')
            )
  from planned_routes r
  left join profiles p on p.user_id = r.user_id
  where r.share_token = token
    and r.is_public = true
  limit 1;
$$;

revoke all on function get_shared_route(uuid) from public;
grant execute on function get_shared_route(uuid) to anon, authenticated;

-- 4) Live riders for a shared route. The invite token is the key: no token,
--    no positions; route unshared, no positions. user_id is never returned.
create or replace function get_live_riders(token uuid)
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
  from planned_routes r
  join live_positions lp on lp.route_id = r.id
  left join profiles p on p.user_id = lp.user_id
  where r.share_token = token
    and r.is_public = true
    and lp.updated_at > now() - interval '5 minutes';
$$;

revoke all on function get_live_riders(uuid) from public;
grant execute on function get_live_riders(uuid) to anon, authenticated;
