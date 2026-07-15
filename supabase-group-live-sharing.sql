-- ============================================================
-- Memory Lanes: explicit group live-location consent
-- ============================================================
-- Live sharing is deliberately separate from RSVP and check-in. Clients can
-- only enable and publish through the authenticated functions below; direct
-- writes remain available solely for the original non-group shared-route flow.

begin;

alter table public.live_positions
  add column if not exists expires_at timestamptz;

create index if not exists live_positions_group_fresh_idx
  on public.live_positions (group_ride_id, expires_at desc)
  where group_ride_id is not null;

create table if not exists public.group_live_sharing_consents (
  group_ride_id uuid not null references public.group_rides(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_shared_at timestamptz,
  primary key (group_ride_id, user_id),
  constraint group_live_consent_expiry_after_start check (expires_at > started_at)
);

create index if not exists group_live_consents_expiry_idx
  on public.group_live_sharing_consents (expires_at);

alter table public.group_live_sharing_consents enable row level security;

-- Consent rows are an audit boundary, not a client-readable data surface.
revoke all on table public.group_live_sharing_consents from public, anon, authenticated;

drop policy if exists "owners insert own live position" on public.live_positions;
drop policy if exists "owners update own live position" on public.live_positions;
drop policy if exists "owners insert own non-group live position" on public.live_positions;
drop policy if exists "owners update own non-group live position" on public.live_positions;

create policy "owners insert own non-group live position"
  on public.live_positions
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id and group_ride_id is null);

create policy "owners update own non-group live position"
  on public.live_positions
  for update
  to authenticated
  using ((select auth.uid()) = user_id and group_ride_id is null)
  with check ((select auth.uid()) = user_id and group_ride_id is null);

create or replace function public.set_group_live_sharing(token uuid, enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rider_id uuid := (select auth.uid());
  ride public.group_rides%rowtype;
  consent_expires_at timestamptz;
begin
  if rider_id is null then
    raise exception 'Authentication required';
  end if;

  select g.* into ride
  from public.group_rides g
  where g.share_token = token
  limit 1;

  if ride.id is null then
    raise exception 'Group ride unavailable';
  end if;

  if not enabled then
    delete from public.live_positions
    where user_id = rider_id and group_ride_id = ride.id;

    delete from public.group_live_sharing_consents
    where group_ride_id = ride.id and user_id = rider_id;

    return jsonb_build_object('enabled', false, 'expires_at', null);
  end if;

  if ride.status <> 'scheduled' or not ride.is_active or not (
    ride.owner_id = rider_id
    or exists (
      select 1
      from public.group_ride_members member
      where member.group_ride_id = ride.id
        and member.user_id = rider_id
        and member.rsvp = 'going'
    )
  ) then
    raise exception 'Only the host or a rider marked Riding can share with this group';
  end if;

  consent_expires_at := least(
    now() + interval '12 hours',
    coalesce(ride.meet_time + interval '12 hours', now() + interval '12 hours')
  );

  if consent_expires_at <= now() then
    raise exception 'This group ride live-sharing window has closed';
  end if;

  -- A rider can broadcast one active ride at a time. Switching rides revokes
  -- the older consent and position before the new session begins.
  delete from public.live_positions
  where user_id = rider_id and group_ride_id is not null;

  delete from public.group_live_sharing_consents
  where user_id = rider_id and group_ride_id <> ride.id;

  insert into public.group_live_sharing_consents (
    group_ride_id, user_id, started_at, expires_at, last_shared_at
  ) values (
    ride.id, rider_id, now(), consent_expires_at, null
  )
  on conflict (group_ride_id, user_id) do update
  set started_at = excluded.started_at,
      expires_at = excluded.expires_at,
      last_shared_at = null;

  return jsonb_build_object(
    'enabled', true,
    'expires_at', consent_expires_at
  );
end;
$$;

create or replace function public.publish_group_live_position(
  token uuid,
  lat double precision,
  lng double precision,
  speed_kmh double precision default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  rider_id uuid := (select auth.uid());
  ride_id uuid;
  planned_route_id uuid;
  consent_expires_at timestamptz;
  position_expires_at timestamptz;
begin
  if rider_id is null then
    raise exception 'Authentication required';
  end if;

  if lat is null or lat < -90 or lat > 90
     or lng is null or lng < -180 or lng > 180
     or (speed_kmh is not null and (speed_kmh < 0 or speed_kmh > 350)) then
    raise exception 'Invalid live position';
  end if;

  select g.id, g.route_id, consent.expires_at
    into ride_id, planned_route_id, consent_expires_at
  from public.group_rides g
  join public.group_live_sharing_consents consent
    on consent.group_ride_id = g.id
   and consent.user_id = rider_id
  where g.share_token = token
    and g.status = 'scheduled'
    and g.is_active = true
    and consent.expires_at > now()
    and (
      g.owner_id = rider_id
      or exists (
        select 1
        from public.group_ride_members member
        where member.group_ride_id = g.id
          and member.user_id = rider_id
          and member.rsvp = 'going'
      )
    )
  limit 1;

  if ride_id is null then
    raise exception 'Live sharing is not enabled for this group ride';
  end if;

  position_expires_at := least(consent_expires_at, now() + interval '2 minutes');

  insert into public.live_positions (
    user_id, route_id, group_ride_id, lat, lng, speed_kmh, updated_at, expires_at
  ) values (
    rider_id, planned_route_id, ride_id, lat, lng, speed_kmh, now(), position_expires_at
  )
  on conflict (user_id) do update
  set route_id = excluded.route_id,
      group_ride_id = excluded.group_ride_id,
      lat = excluded.lat,
      lng = excluded.lng,
      speed_kmh = excluded.speed_kmh,
      updated_at = excluded.updated_at,
      expires_at = excluded.expires_at;

  update public.group_live_sharing_consents
  set last_shared_at = now()
  where group_ride_id = ride_id and user_id = rider_id;

  -- Opportunistic cleanup keeps private rows short-lived even when pg_cron is
  -- unavailable on a project plan. Reads also exclude expired rows immediately.
  delete from public.live_positions
  where group_ride_id is not null and expires_at <= now();

  delete from public.group_live_sharing_consents
  where expires_at <= now();

  return true;
end;
$$;

create or replace function public.get_group_live_riders(token uuid)
returns jsonb
language sql
security definer
stable
set search_path = ''
as $$
  select case when (select auth.uid()) is not null and exists (
    select 1
    from public.group_rides access_ride
    where access_ride.share_token = token
      and access_ride.status = 'scheduled'
      and access_ride.is_active = true
      and (
        access_ride.owner_id = (select auth.uid())
        or exists (
          select 1
          from public.group_ride_members access_member
          where access_member.group_ride_id = access_ride.id
            and access_member.user_id = (select auth.uid())
            and access_member.rsvp = 'going'
        )
      )
  ) then coalesce((
    select jsonb_agg(jsonb_build_object(
      'name', coalesce(nullif(trim(coalesce(profile.display_name, '')), ''), 'A rider'),
      'lat', position.lat,
      'lng', position.lng,
      'speed_kmh', position.speed_kmh,
      'updated_at', position.updated_at
    ) order by position.updated_at desc)
    from public.group_rides ride
    join public.live_positions position on position.group_ride_id = ride.id
    join public.group_live_sharing_consents consent
      on consent.group_ride_id = ride.id
     and consent.user_id = position.user_id
    left join public.profiles profile on profile.user_id = position.user_id
    where ride.share_token = token
      and ride.status = 'scheduled'
      and ride.is_active = true
      and consent.expires_at > now()
      and position.expires_at > now()
      and position.updated_at > now() - interval '2 minutes'
      and position.user_id <> (select auth.uid())
  ), '[]'::jsonb) else '[]'::jsonb end;
$$;

revoke all on function public.set_group_live_sharing(uuid, boolean) from public, anon, authenticated;
revoke all on function public.publish_group_live_position(uuid, double precision, double precision, double precision) from public, anon, authenticated;
revoke all on function public.get_group_live_riders(uuid) from public, anon, authenticated;

grant execute on function public.set_group_live_sharing(uuid, boolean) to authenticated;
grant execute on function public.publish_group_live_position(uuid, double precision, double precision, double precision) to authenticated;
grant execute on function public.get_group_live_riders(uuid) to authenticated;

commit;
