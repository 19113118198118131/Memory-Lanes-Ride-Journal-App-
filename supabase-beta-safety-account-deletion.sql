-- Memory Lanes: beta safety, account deletion and community controls.
-- Apply after the existing group ride migrations.

begin;

create table if not exists public.account_deletion_requests (
  user_id uuid primary key references auth.users(id) on delete cascade,
  requested_at timestamptz not null default now(),
  status text not null default 'requested',
  updated_at timestamptz not null default now(),
  constraint account_deletion_requests_status_check
    check (status in ('requested', 'processing', 'completed', 'cancelled'))
);

alter table public.account_deletion_requests enable row level security;
drop policy if exists "users read own deletion request" on public.account_deletion_requests;
create policy "users read own deletion request" on public.account_deletion_requests
  for select to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists public.community_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  group_ride_id uuid not null references public.group_rides(id) on delete cascade,
  reason text not null,
  detail text,
  status text not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_reports_reason_check
    check (reason in ('safety', 'abusive', 'misleading', 'other')),
  constraint community_reports_detail_length_check
    check (detail is null or char_length(detail) <= 1000),
  constraint community_reports_status_check
    check (status in ('open', 'reviewing', 'resolved', 'dismissed'))
);

create unique index if not exists community_reports_reporter_ride_key
  on public.community_reports (reporter_id, group_ride_id);
alter table public.community_reports enable row level security;
drop policy if exists "reporters read own community reports" on public.community_reports;
create policy "reporters read own community reports" on public.community_reports
  for select to authenticated
  using ((select auth.uid()) = reporter_id);

create table if not exists public.blocked_riders (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocked_riders_not_self_check check (blocker_id <> blocked_id)
);

alter table public.blocked_riders enable row level security;
drop policy if exists "users read own blocks" on public.blocked_riders;
drop policy if exists "users create own blocks" on public.blocked_riders;
drop policy if exists "users remove own blocks" on public.blocked_riders;
create policy "users read own blocks" on public.blocked_riders
  for select to authenticated using ((select auth.uid()) = blocker_id);
create policy "users create own blocks" on public.blocked_riders
  for insert to authenticated with check ((select auth.uid()) = blocker_id);
create policy "users remove own blocks" on public.blocked_riders
  for delete to authenticated using ((select auth.uid()) = blocker_id);

create or replace function public.request_account_deletion()
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  uid uuid;
begin
  uid := (select auth.uid());
  if uid is null then
    raise exception 'Sign in before requesting account deletion.' using errcode = 'P0001';
  end if;

  insert into public.account_deletion_requests (user_id, requested_at, updated_at, status)
  values (uid, now(), now(), 'requested')
  on conflict (user_id) do update
  set requested_at = excluded.requested_at,
      updated_at = excluded.updated_at,
      status = case
        when public.account_deletion_requests.status = 'completed' then 'completed'
        else 'requested'
      end;
  return true;
end;
$$;

create or replace function public.report_group_ride(
  token uuid,
  report_reason text,
  report_detail text default null
)
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  uid uuid;
  gid uuid;
  clean_detail text;
begin
  uid := (select auth.uid());
  if uid is null then
    raise exception 'Sign in before reporting a group ride.' using errcode = 'P0001';
  end if;
  if report_reason not in ('safety', 'abusive', 'misleading', 'other') then
    raise exception 'Choose a report reason.' using errcode = 'P0001';
  end if;
  clean_detail := nullif(trim(coalesce(report_detail, '')), '');
  if clean_detail is not null and char_length(clean_detail) > 1000 then
    raise exception 'Report details are limited to 1000 characters.' using errcode = 'P0001';
  end if;

  select g.id into gid
  from public.group_rides g
  where g.share_token = token
  limit 1;
  if gid is null then
    raise exception 'This group ride is no longer available.' using errcode = 'P0001';
  end if;

  insert into public.community_reports (reporter_id, group_ride_id, reason, detail, status, updated_at)
  values (uid, gid, report_reason, clean_detail, 'open', now())
  on conflict (reporter_id, group_ride_id) do update
  set reason = excluded.reason,
      detail = excluded.detail,
      status = 'open',
      updated_at = now();
  return true;
end;
$$;

create or replace function public.block_group_ride_host(token uuid)
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  uid uuid;
  host_id uuid;
begin
  uid := (select auth.uid());
  if uid is null then
    raise exception 'Sign in before blocking a host.' using errcode = 'P0001';
  end if;

  select g.owner_id into host_id
  from public.group_rides g
  where g.share_token = token
  limit 1;
  if host_id is null or host_id = uid then
    raise exception 'That host cannot be blocked from this ride.' using errcode = 'P0001';
  end if;

  insert into public.blocked_riders (blocker_id, blocked_id)
  values (uid, host_id)
  on conflict (blocker_id, blocked_id) do nothing;

  delete from public.group_ride_members membership
  using public.group_rides ride
  where membership.group_ride_id = ride.id
    and membership.user_id = uid
    and ride.owner_id = host_id;
  return true;
end;
$$;

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
    'member_count', (select count(*) from public.group_ride_members m where m.group_ride_id = g.id and m.rsvp in ('going', 'maybe')),
    'going_count', (select count(*) from public.group_ride_members m where m.group_ride_id = g.id and m.rsvp = 'going'),
    'maybe_count', (select count(*) from public.group_ride_members m where m.group_ride_id = g.id and m.rsvp = 'maybe'),
    'declined_count', (select count(*) from public.group_ride_members m where m.group_ride_id = g.id and m.rsvp = 'no'),
    'is_owner', ((select auth.uid()) is not null and (select auth.uid()) = g.owner_id),
    'is_member', ((select auth.uid()) is not null and exists (select 1 from public.group_ride_members m where m.group_ride_id = g.id and m.user_id = (select auth.uid()))),
    'your_rsvp', (select m.rsvp from public.group_ride_members m where m.group_ride_id = g.id and m.user_id = (select auth.uid())),
    'members', case when (select auth.uid()) = g.owner_id or exists (
      select 1 from public.group_ride_members own_membership
      where own_membership.group_ride_id = g.id and own_membership.user_id = (select auth.uid())
    ) then (
      select coalesce(jsonb_agg(jsonb_build_object(
        'name', coalesce(nullif(trim(coalesce(pm.display_name, '')), ''), 'A rider'),
        'rsvp', m.rsvp,
        'is_you', ((select auth.uid()) is not null and (select auth.uid()) = m.user_id)
      ) order by case m.rsvp when 'going' then 0 when 'maybe' then 1 else 2 end, m.joined_at), '[]'::jsonb)
      from public.group_ride_members m
      left join public.profiles pm on pm.user_id = m.user_id
      where m.group_ride_id = g.id
    ) else '[]'::jsonb end,
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
    and not exists (
      select 1 from public.blocked_riders b
      where b.blocker_id = (select auth.uid()) and b.blocked_id = g.owner_id
    )
    and (g.status = 'scheduled' or (select auth.uid()) = g.owner_id or exists (
      select 1 from public.group_ride_members m
      where m.group_ride_id = g.id and m.user_id = (select auth.uid())
    ))
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
  if (select auth.uid()) is null then return null; end if;
  if answer not in ('going', 'maybe', 'no') then
    raise exception 'Choose Riding, Maybe, or Not this time.' using errcode = 'P0001';
  end if;

  select g.id, g.capacity into gid, ride_capacity
  from public.group_rides g
  where g.share_token = token and g.status = 'scheduled' and g.is_active = true
    and not exists (
      select 1 from public.blocked_riders b
      where b.blocker_id = (select auth.uid()) and b.blocked_id = g.owner_id
    )
  limit 1 for update of g;
  if gid is null then return null; end if;

  select m.rsvp into current_answer
  from public.group_ride_members m
  where m.group_ride_id = gid and m.user_id = (select auth.uid());
  if answer = 'going' and ride_capacity is not null and current_answer is distinct from 'going' then
    select count(*) into confirmed_count from public.group_ride_members m
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
      'title', g.title, 'details', g.details, 'share_token', g.share_token,
      'meet_time', g.meet_time, 'hosted_by', nullif(trim(coalesce(p.display_name, '')), ''),
      'host_region', nullif(trim(coalesce(p.region, '')), ''), 'capacity', g.capacity,
      'going_count', (select count(*) from public.group_ride_members m where m.group_ride_id = g.id and m.rsvp = 'going'),
      'maybe_count', (select count(*) from public.group_ride_members m where m.group_ride_id = g.id and m.rsvp = 'maybe'),
      'route_title', r.title, 'distance_km', r.distance_km, 'elevation_m', r.elevation_m
    ) as payload
    from public.group_rides g
    join public.planned_routes r on r.id = g.route_id
    left join public.profiles p on p.user_id = g.owner_id
    where (select auth.uid()) is not null
      and g.visibility = 'community' and g.status = 'scheduled' and g.is_active = true
      and g.owner_id <> (select auth.uid())
      and not exists (
        select 1 from public.blocked_riders b
        where b.blocker_id = (select auth.uid()) and b.blocked_id = g.owner_id
      )
      and (g.meet_time is null or g.meet_time > now() - interval '2 hours')
    order by g.meet_time nulls last, g.created_at desc
    limit greatest(1, least(coalesce(max_results, 20), 50))
  ) upcoming;
$$;

revoke all on function public.request_account_deletion() from public, anon, authenticated;
revoke all on function public.report_group_ride(uuid, text, text) from public, anon, authenticated;
revoke all on function public.block_group_ride_host(uuid) from public, anon, authenticated;
grant execute on function public.request_account_deletion() to authenticated;
grant execute on function public.report_group_ride(uuid, text, text) to authenticated;
grant execute on function public.block_group_ride_host(uuid) to authenticated;

commit;
