-- Memory Lanes: production group-ride and community event contract.
-- Idempotent upgrade for supabase-groupride-setup.sql and
-- supabase-groupmeet-setup.sql.

begin;

alter table public.group_rides
  add column if not exists details text,
  add column if not exists visibility text not null default 'invite_only',
  add column if not exists capacity integer,
  add column if not exists status text not null default 'scheduled',
  add column if not exists updated_at timestamptz not null default now();

update public.group_rides
set status = 'completed'
where is_active = false and status = 'scheduled';

alter table public.group_rides drop constraint if exists group_rides_visibility_check;
alter table public.group_rides add constraint group_rides_visibility_check
  check (visibility in ('invite_only', 'community'));

alter table public.group_rides drop constraint if exists group_rides_status_check;
alter table public.group_rides add constraint group_rides_status_check
  check (status in ('scheduled', 'cancelled', 'completed'));

alter table public.group_rides drop constraint if exists group_rides_capacity_check;
alter table public.group_rides add constraint group_rides_capacity_check
  check (capacity is null or capacity between 2 and 100);

alter table public.group_rides drop constraint if exists group_rides_details_length_check;
alter table public.group_rides add constraint group_rides_details_length_check
  check (details is null or char_length(details) <= 1000);

create index if not exists group_rides_discovery_idx
  on public.group_rides (visibility, status, meet_time)
  where visibility = 'community' and status = 'scheduled';
create index if not exists group_ride_members_user_rsvp_idx
  on public.group_ride_members (user_id, rsvp, group_ride_id);

create or replace function public.enforce_group_ride_capacity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  confirmed_count integer;
begin
  if new.capacity is null then
    return new;
  end if;
  select count(*) into confirmed_count
  from public.group_ride_members m
  where m.group_ride_id = new.id and m.rsvp = 'going';
  if confirmed_count > new.capacity then
    raise exception 'Capacity cannot be lower than the confirmed rider count.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists group_rides_capacity_guard on public.group_rides;
create trigger group_rides_capacity_guard
before insert or update of capacity on public.group_rides
for each row execute function public.enforce_group_ride_capacity();

drop policy if exists "owners select own group rides" on public.group_rides;
drop policy if exists "owners insert own group rides" on public.group_rides;
drop policy if exists "owners update own group rides" on public.group_rides;
drop policy if exists "owners delete own group rides" on public.group_rides;

create policy "owners select own group rides" on public.group_rides
  for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy "owners insert own group rides" on public.group_rides
  for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy "owners update own group rides" on public.group_rides
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy "owners delete own group rides" on public.group_rides
  for delete to authenticated
  using ((select auth.uid()) = owner_id);

drop policy if exists "members select own membership" on public.group_ride_members;
drop policy if exists "members delete own membership" on public.group_ride_members;

create policy "members select own membership" on public.group_ride_members
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "members delete own membership" on public.group_ride_members
  for delete to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.group_rides to authenticated;
grant select, delete on public.group_ride_members to authenticated;

create or replace function public.get_group_ride(token uuid)
returns jsonb
language sql
security definer
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', g.id,
    'title', g.title,
    'details', g.details,
    'visibility', g.visibility,
    'capacity', g.capacity,
    'status', g.status,
    'is_active', g.is_active,
    'created_at', g.created_at,
    'meet_time', g.meet_time,
    'meet_point', g.meet_point,
    'hosted_by', nullif(trim(coalesce(p.display_name, '')), ''),
    'member_count', (select count(*) from public.group_ride_members m
      where m.group_ride_id = g.id and m.rsvp in ('going', 'maybe')),
    'going_count', (select count(*) from public.group_ride_members m
      where m.group_ride_id = g.id and m.rsvp = 'going'),
    'maybe_count', (select count(*) from public.group_ride_members m
      where m.group_ride_id = g.id and m.rsvp = 'maybe'),
    'declined_count', (select count(*) from public.group_ride_members m
      where m.group_ride_id = g.id and m.rsvp = 'no'),
    'is_owner', ((select auth.uid()) is not null and (select auth.uid()) = g.owner_id),
    'is_member', ((select auth.uid()) is not null and exists (
      select 1 from public.group_ride_members m
      where m.group_ride_id = g.id and m.user_id = (select auth.uid())
    )),
    'your_rsvp', (select m.rsvp from public.group_ride_members m
      where m.group_ride_id = g.id and m.user_id = (select auth.uid())),
    'members', case when
      (select auth.uid()) = g.owner_id or exists (
        select 1 from public.group_ride_members own_membership
        where own_membership.group_ride_id = g.id
          and own_membership.user_id = (select auth.uid())
      )
      then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'name', coalesce(nullif(trim(coalesce(pm.display_name, '')), ''), 'A rider'),
          'rsvp', m.rsvp,
          'is_you', ((select auth.uid()) is not null and (select auth.uid()) = m.user_id)
        ) order by
          case m.rsvp when 'going' then 0 when 'maybe' then 1 else 2 end,
          m.joined_at), '[]'::jsonb)
        from public.group_ride_members m
        left join public.profiles pm on pm.user_id = m.user_id
        where m.group_ride_id = g.id
      )
      else '[]'::jsonb
    end,
    'route_id', r.id,
    'route_title', r.title,
    'distance_km', r.distance_km,
    'elevation_m', r.elevation_m,
    'route', r.route
  )
  from public.group_rides g
  join public.planned_routes r on r.id = g.route_id
  left join public.profiles p on p.user_id = g.owner_id
  where g.share_token = token
    and (
      g.status = 'scheduled'
      or (select auth.uid()) = g.owner_id
      or exists (
        select 1 from public.group_ride_members m
        where m.group_ride_id = g.id and m.user_id = (select auth.uid())
      )
    )
  limit 1;
$$;

create or replace function public.rsvp_group_ride(token uuid, answer text)
returns jsonb
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  gid uuid;
  ride_capacity integer;
  confirmed_count integer;
  current_answer text;
begin
  if (select auth.uid()) is null then
    return null;
  end if;
  if answer not in ('going', 'maybe', 'no') then
    raise exception 'Choose Riding, Maybe, or Not this time.' using errcode = 'P0001';
  end if;

  select g.id, g.capacity into gid, ride_capacity
  from public.group_rides g
  where g.share_token = token and g.status = 'scheduled' and g.is_active = true
  limit 1
  for update of g;
  if gid is null then
    return null;
  end if;

  select m.rsvp into current_answer
  from public.group_ride_members m
  where m.group_ride_id = gid and m.user_id = (select auth.uid());

  if answer = 'going' and ride_capacity is not null and current_answer is distinct from 'going' then
    select count(*) into confirmed_count
    from public.group_ride_members m
    where m.group_ride_id = gid and m.rsvp = 'going';
    if confirmed_count >= ride_capacity then
      raise exception 'This group ride is full.' using errcode = 'P0001';
    end if;
  end if;

  insert into public.group_ride_members (group_ride_id, user_id, rsvp)
  values (gid, (select auth.uid()), answer)
  on conflict (group_ride_id, user_id) do update set rsvp = excluded.rsvp;
  return public.get_group_ride(token);
end;
$$;

create or replace function public.join_group_ride(token uuid)
returns jsonb
language plpgsql
security definer
volatile
set search_path = ''
as $$
begin
  return public.rsvp_group_ride(token, 'going');
end;
$$;

create or replace function public.leave_group_ride(token uuid)
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  gid uuid;
  host_id uuid;
begin
  if (select auth.uid()) is null then
    return false;
  end if;
  select g.id, g.owner_id into gid, host_id
  from public.group_rides g where g.share_token = token limit 1;
  if gid is null or host_id = (select auth.uid()) then
    return false;
  end if;
  delete from public.group_ride_members m
  where m.group_ride_id = gid and m.user_id = (select auth.uid());
  return found;
end;
$$;

create or replace function public.set_group_ride_status(token uuid, new_status text)
returns jsonb
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  gid uuid;
begin
  if (select auth.uid()) is null then
    return null;
  end if;
  if new_status not in ('cancelled', 'completed') then
    raise exception 'Unsupported group ride status.' using errcode = 'P0001';
  end if;
  update public.group_rides g
  set status = new_status,
      is_active = false,
      updated_at = now()
  where g.share_token = token
    and g.owner_id = (select auth.uid())
    and g.status = 'scheduled'
  returning g.id into gid;
  if gid is null then
    return null;
  end if;
  return public.get_group_ride(token);
end;
$$;

create or replace function public.get_my_group_rides()
returns jsonb
language sql
security definer
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'title', x.title,
    'details', x.details,
    'visibility', x.visibility,
    'capacity', x.capacity,
    'status', x.status,
    'share_token', x.share_token,
    'meet_time', x.meet_time,
    'meet_point', x.meet_point,
    'created_at', x.created_at,
    'is_owner', x.is_owner,
    'your_rsvp', x.your_rsvp,
    'member_count', x.member_count,
    'going_count', x.going_count,
    'maybe_count', x.maybe_count,
    'declined_count', x.declined_count,
    'route_title', x.route_title
  ) order by coalesce(x.meet_time, x.created_at)), '[]'::jsonb)
  from (
    select g.title, g.details, g.visibility, g.capacity, g.status, g.share_token,
      g.meet_time, g.meet_point, g.created_at, true as is_owner,
      null::text as your_rsvp,
      (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp in ('going', 'maybe')) as member_count,
      (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp = 'going') as going_count,
      (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp = 'maybe') as maybe_count,
      (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp = 'no') as declined_count,
      r.title as route_title
    from public.group_rides g
    join public.planned_routes r on r.id = g.route_id
    where g.owner_id = (select auth.uid()) and g.status = 'scheduled'
    union all
    select g.title, g.details, g.visibility, g.capacity, g.status, g.share_token,
      g.meet_time, g.meet_point, g.created_at, false as is_owner,
      mm.rsvp as your_rsvp,
      (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp in ('going', 'maybe')) as member_count,
      (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp = 'going') as going_count,
      (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp = 'maybe') as maybe_count,
      (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp = 'no') as declined_count,
      r.title as route_title
    from public.group_ride_members mm
    join public.group_rides g on g.id = mm.group_ride_id
    join public.planned_routes r on r.id = g.route_id
    where mm.user_id = (select auth.uid())
      and mm.rsvp <> 'no'
      and g.owner_id <> (select auth.uid())
      and g.status = 'scheduled'
  ) x;
$$;

create or replace function public.discover_group_rides(max_results integer default 20)
returns jsonb
language sql
security definer
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(upcoming.payload order by upcoming.meet_time), '[]'::jsonb)
  from (
    select g.meet_time, jsonb_build_object(
      'title', g.title,
      'details', g.details,
      'share_token', g.share_token,
      'meet_time', g.meet_time,
      'hosted_by', nullif(trim(coalesce(p.display_name, '')), ''),
      'host_region', nullif(trim(coalesce(p.region, '')), ''),
      'capacity', g.capacity,
      'going_count', (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp = 'going'),
      'maybe_count', (select count(*) from public.group_ride_members m
        where m.group_ride_id = g.id and m.rsvp = 'maybe'),
      'route_title', r.title,
      'distance_km', r.distance_km,
      'elevation_m', r.elevation_m
    ) as payload
    from public.group_rides g
    join public.planned_routes r on r.id = g.route_id
    left join public.profiles p on p.user_id = g.owner_id
    where (select auth.uid()) is not null
      and g.visibility = 'community'
      and g.status = 'scheduled'
      and g.is_active = true
      and g.owner_id <> (select auth.uid())
      and (g.meet_time is null or g.meet_time > now() - interval '2 hours')
    order by g.meet_time nulls last, g.created_at desc
    limit greatest(1, least(coalesce(max_results, 20), 50))
  ) upcoming;
$$;

create or replace function public.get_group_live_riders(token uuid)
returns jsonb
language sql
security definer
stable
set search_path = ''
as $$
  select case when (select auth.uid()) is not null and exists (
    select 1 from public.group_rides access_ride
    where access_ride.share_token = token
      and access_ride.status = 'scheduled'
      and (
        access_ride.owner_id = (select auth.uid())
        or exists (
          select 1 from public.group_ride_members access_member
          where access_member.group_ride_id = access_ride.id
            and access_member.user_id = (select auth.uid())
            and access_member.rsvp = 'going'
        )
      )
  ) then coalesce((
    select jsonb_agg(jsonb_build_object(
      'name', coalesce(nullif(trim(coalesce(p.display_name, '')), ''), 'A rider'),
      'lat', lp.lat,
      'lng', lp.lng,
      'speed_kmh', lp.speed_kmh,
      'updated_at', lp.updated_at
    ) order by lp.updated_at desc)
    from public.group_rides g
    join public.live_positions lp on lp.group_ride_id = g.id
    left join public.profiles p on p.user_id = lp.user_id
    where g.share_token = token
      and g.status = 'scheduled'
      and lp.updated_at > now() - interval '5 minutes'
      and lp.user_id <> (select auth.uid())
  ), '[]'::jsonb) else '[]'::jsonb end;
$$;

revoke all on function public.get_group_ride(uuid) from public, anon, authenticated;
revoke all on function public.rsvp_group_ride(uuid, text) from public, anon, authenticated;
revoke all on function public.join_group_ride(uuid) from public, anon, authenticated;
revoke all on function public.leave_group_ride(uuid) from public, anon, authenticated;
revoke all on function public.set_group_ride_status(uuid, text) from public, anon, authenticated;
revoke all on function public.get_my_group_rides() from public, anon, authenticated;
revoke all on function public.discover_group_rides(integer) from public, anon, authenticated;
revoke all on function public.get_group_live_riders(uuid) from public, anon, authenticated;
revoke all on function public.enforce_group_ride_capacity() from public, anon, authenticated;

grant execute on function public.get_group_ride(uuid) to anon, authenticated;
grant execute on function public.rsvp_group_ride(uuid, text) to authenticated;
grant execute on function public.join_group_ride(uuid) to authenticated;
grant execute on function public.leave_group_ride(uuid) to authenticated;
grant execute on function public.set_group_ride_status(uuid, text) to authenticated;
grant execute on function public.get_my_group_rides() to authenticated;
grant execute on function public.discover_group_rides(integer) to authenticated;
grant execute on function public.get_group_live_riders(uuid) to authenticated;

commit;
