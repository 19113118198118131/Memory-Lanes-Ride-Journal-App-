-- ============================================================
-- Memory Lanes: Group Ride meetups, RSVP, and "My Group Rides"
-- Run this in Supabase Dashboard -> SQL Editor -> New query
-- (Extends supabase-groupride-setup.sql.)
-- ============================================================

-- 1) Meeting details, set by the host from the lobby page.
alter table group_rides add column if not exists meet_time timestamptz;
alter table group_rides add column if not exists meet_point text;

-- 2) RSVP on membership: joining defaults to 'going'; riders can change
--    their answer from the lobby without leaving the group.
alter table group_ride_members add column if not exists rsvp text not null default 'going';
alter table group_ride_members drop constraint if exists group_ride_members_rsvp_check;
alter table group_ride_members add constraint group_ride_members_rsvp_check
  check (rsvp in ('going', 'maybe', 'no'));

-- 3) get_group_ride now returns meeting details, the attendee list
--    (display names + rsvp only, never user ids), and the caller's own rsvp.
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
    'meet_time', g.meet_time,
    'meet_point', g.meet_point,
    'hosted_by', nullif(trim(coalesce(p.display_name, '')), ''),
    'member_count', (select count(*) from group_ride_members m where m.group_ride_id = g.id),
    'is_owner', (auth.uid() is not null and auth.uid() = g.owner_id),
    'is_member', (auth.uid() is not null and exists (
       select 1 from group_ride_members m where m.group_ride_id = g.id and m.user_id = auth.uid())),
    'your_rsvp', (select m.rsvp from group_ride_members m
       where m.group_ride_id = g.id and m.user_id = auth.uid()),
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'name', coalesce(nullif(trim(coalesce(pm.display_name, '')), ''), 'A rider'),
        'rsvp', m.rsvp,
        'is_you', (auth.uid() is not null and auth.uid() = m.user_id)
      ) order by m.joined_at), '[]'::jsonb)
      from group_ride_members m
      left join profiles pm on pm.user_id = m.user_id
      where m.group_ride_id = g.id
    ),
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

-- 4) RSVP from the lobby. Creates the membership if needed, so "I'm in"
--    works as the confirm-attendance action for first-timers too.
create or replace function rsvp_group_ride(token uuid, answer text)
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
  if answer not in ('going', 'maybe', 'no') then
    return null;
  end if;
  select g.id into gid from group_rides g
    where g.share_token = token and g.is_active = true limit 1;
  if gid is null then
    return null;
  end if;
  insert into group_ride_members (group_ride_id, user_id, rsvp)
    values (gid, auth.uid(), answer)
    on conflict (group_ride_id, user_id) do update set rsvp = excluded.rsvp;
  return get_group_ride(token);
end;
$$;

revoke all on function rsvp_group_ride(uuid, text) from public;
grant execute on function rsvp_group_ride(uuid, text) to authenticated;

-- 5) Actually starting to ride marks you as going, whatever you said before.
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
  insert into group_ride_members (group_ride_id, user_id, rsvp)
    values (gid, auth.uid(), 'going')
    on conflict (group_ride_id, user_id) do update set rsvp = 'going';
  return get_group_ride(token);
end;
$$;

revoke all on function join_group_ride(uuid) from public;
grant execute on function join_group_ride(uuid) to authenticated;

-- 6) "My Group Rides": every active group ride you host or have joined,
--    with the share token so the app can rebuild the lobby link (losing
--    the link no longer means asking the host). Caller's own rides only.
create or replace function get_my_group_rides()
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'title', x.title,
    'share_token', x.share_token,
    'meet_time', x.meet_time,
    'meet_point', x.meet_point,
    'created_at', x.created_at,
    'is_owner', x.is_owner,
    'member_count', x.member_count,
    'route_title', x.route_title
  ) order by coalesce(x.meet_time, x.created_at) desc), '[]'::jsonb)
  from (
    select g.title, g.share_token, g.meet_time, g.meet_point, g.created_at,
           true as is_owner,
           (select count(*) from group_ride_members m where m.group_ride_id = g.id) as member_count,
           r.title as route_title
    from group_rides g
    join planned_routes r on r.id = g.route_id
    where g.owner_id = auth.uid() and g.is_active = true
    union all
    select g.title, g.share_token, g.meet_time, g.meet_point, g.created_at,
           false as is_owner,
           (select count(*) from group_ride_members m where m.group_ride_id = g.id) as member_count,
           r.title as route_title
    from group_ride_members mm
    join group_rides g on g.id = mm.group_ride_id
    join planned_routes r on r.id = g.route_id
    where mm.user_id = auth.uid() and g.owner_id <> auth.uid() and g.is_active = true
  ) x;
$$;

revoke all on function get_my_group_rides() from public;
grant execute on function get_my_group_rides() to authenticated;
