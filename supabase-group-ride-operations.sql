-- Memory Lanes: ride-day check-in, organiser readiness and host announcements.
-- Depends on supabase-group-social-production.sql and supabase-group-notifications.sql.

begin;

alter table public.group_rides
  add column if not exists host_checked_in_at timestamptz;

alter table public.group_ride_members
  add column if not exists checked_in_at timestamptz;

create index if not exists group_ride_members_checked_in_idx
  on public.group_ride_members (group_ride_id, checked_in_at)
  where checked_in_at is not null;

create table if not exists public.group_ride_announcements (
  id uuid primary key default gen_random_uuid(),
  group_ride_id uuid not null references public.group_rides(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now(),
  constraint group_ride_announcements_message_length
    check (char_length(trim(message)) between 1 and 500)
);

create index if not exists group_ride_announcements_ride_created_idx
  on public.group_ride_announcements (group_ride_id, created_at desc);
create index if not exists group_ride_announcements_author_idx
  on public.group_ride_announcements (author_id);

alter table public.group_ride_announcements enable row level security;

drop policy if exists "clients cannot access group ride announcements" on public.group_ride_announcements;
create policy "clients cannot access group ride announcements"
  on public.group_ride_announcements
  for all to authenticated
  using (false)
  with check (false);

revoke all on public.group_ride_announcements from public, anon, authenticated;

alter table public.notification_outbox
  drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox
  add constraint notification_outbox_kind_check
  check (kind in (
    'group_rsvp',
    'group_updated',
    'group_cancelled',
    'group_announcement',
    'ride_reminder'
  ));

create or replace function public.get_group_ride_operations(token uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  gid uuid;
  host_id uuid;
  ride_status text;
  ride_active boolean;
  ride_meet_time timestamptz;
  base_payload jsonb;
  can_view_operations boolean := false;
  can_check_in boolean := false;
  member_payload jsonb := '[]'::jsonb;
  announcement_payload jsonb := '[]'::jsonb;
begin
  base_payload := public.get_group_ride(token);
  if base_payload is null then
    return null;
  end if;

  select g.id, g.owner_id, g.status, g.is_active, g.meet_time
  into gid, host_id, ride_status, ride_active, ride_meet_time
  from public.group_rides g
  where g.share_token = token
  limit 1;

  can_view_operations := uid is not null and (
    uid = host_id
    or exists (
      select 1
      from public.group_ride_members own_membership
      where own_membership.group_ride_id = gid
        and own_membership.user_id = uid
    )
  );

  can_check_in := can_view_operations
    and ride_status = 'scheduled'
    and ride_active
    and (
      uid = host_id
      or exists (
        select 1
        from public.group_ride_members eligible_membership
        where eligible_membership.group_ride_id = gid
          and eligible_membership.user_id = uid
          and eligible_membership.rsvp in ('going', 'maybe')
      )
    )
    and (
      ride_meet_time is null
      or now() between ride_meet_time - interval '6 hours' and ride_meet_time + interval '12 hours'
    );

  if can_view_operations then
    select coalesce(jsonb_agg(jsonb_build_object(
      'name', coalesce(nullif(trim(coalesce(pm.display_name, '')), ''), 'A rider'),
      'rsvp', m.rsvp,
      'is_you', uid = m.user_id,
      'checked_in_at', case when m.user_id = host_id then g.host_checked_in_at else m.checked_in_at end
    ) order by
      case when (case when m.user_id = host_id then g.host_checked_in_at else m.checked_in_at end) is not null then 0 else 1 end,
      case m.rsvp when 'going' then 0 when 'maybe' then 1 else 2 end,
      m.joined_at), '[]'::jsonb)
    into member_payload
    from public.group_ride_members m
    join public.group_rides g on g.id = m.group_ride_id
    left join public.profiles pm on pm.user_id = m.user_id
    where m.group_ride_id = gid;

    select coalesce(jsonb_agg(recent.payload order by recent.created_at desc), '[]'::jsonb)
    into announcement_payload
    from (
      select a.created_at, jsonb_build_object(
        'id', a.id,
        'message', a.message,
        'created_at', a.created_at,
        'author_name', coalesce(nullif(trim(coalesce(p.display_name, '')), ''), 'Ride organiser'),
        'is_host', a.author_id = host_id
      ) as payload
      from public.group_ride_announcements a
      left join public.profiles p on p.user_id = a.author_id
      where a.group_ride_id = gid
      order by a.created_at desc
      limit 20
    ) recent;
  end if;

  return base_payload || jsonb_build_object(
    'members', member_payload,
    'checked_in_count', case when can_view_operations then (
        select count(*)
        from public.group_ride_members m
        where m.group_ride_id = gid
          and m.user_id <> host_id
          and m.rsvp in ('going', 'maybe')
          and m.checked_in_at is not null
      ) + case when (
        select g.host_checked_in_at is not null from public.group_rides g where g.id = gid
      ) then 1 else 0 end
      else 0
    end,
    'your_checked_in_at', case
      when uid = host_id then (select g.host_checked_in_at from public.group_rides g where g.id = gid)
      else (
        select m.checked_in_at
        from public.group_ride_members m
        where m.group_ride_id = gid and m.user_id = uid
      )
    end,
    'check_in_available', can_check_in,
    'announcements', announcement_payload
  );
end;
$$;

create or replace function public.set_group_ride_check_in(token uuid, checked_in boolean)
returns jsonb
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  ride public.group_rides%rowtype;
begin
  if uid is null then
    return null;
  end if;

  select g.* into ride
  from public.group_rides g
  where g.share_token = token
  limit 1
  for update;

  if ride.id is null or ride.status <> 'scheduled' or not ride.is_active then
    return null;
  end if;

  if ride.meet_time is not null
     and now() not between ride.meet_time - interval '6 hours' and ride.meet_time + interval '12 hours' then
    raise exception 'Check-in opens six hours before the meeting time.' using errcode = 'P0001';
  end if;

  if uid = ride.owner_id then
    update public.group_rides g
    set host_checked_in_at = case when checked_in then now() else null end,
        updated_at = now()
    where g.id = ride.id;
  else
    update public.group_ride_members m
    set checked_in_at = case when checked_in then now() else null end
    where m.group_ride_id = ride.id
      and m.user_id = uid
      and m.rsvp in ('going', 'maybe');
    if not found then
      raise exception 'RSVP Riding or Maybe before checking in.' using errcode = 'P0001';
    end if;
  end if;

  return public.get_group_ride_operations(token);
end;
$$;

create or replace function public.post_group_ride_announcement(token uuid, message text)
returns jsonb
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  ride public.group_rides%rowtype;
  clean_message text := trim(coalesce(message, ''));
  announcement_id uuid;
begin
  if uid is null then
    return null;
  end if;
  if char_length(clean_message) < 1 or char_length(clean_message) > 500 then
    raise exception 'Announcements must be between 1 and 500 characters.' using errcode = 'P0001';
  end if;

  select g.* into ride
  from public.group_rides g
  where g.share_token = token
    and g.owner_id = uid
    and g.status = 'scheduled'
    and g.is_active = true
  limit 1;

  if ride.id is null then
    return null;
  end if;

  insert into public.group_ride_announcements (group_ride_id, author_id, message)
  values (ride.id, uid, clean_message)
  returning id into announcement_id;

  insert into public.notification_outbox (
    recipient_id, group_ride_id, kind, title, body, deep_link, dedupe_key
  )
  select m.user_id, ride.id, 'group_announcement', 'Update from your ride host',
    clean_message, 'memorylanes://group/' || ride.share_token::text,
    'announcement:' || announcement_id::text || ':' || m.user_id::text
  from public.group_ride_members m
  where m.group_ride_id = ride.id
    and m.user_id <> uid
    and m.rsvp in ('going', 'maybe')
    and coalesce((
      select p.event_updates
      from public.notification_preferences p
      where p.user_id = m.user_id
    ), true);

  return public.get_group_ride_operations(token);
end;
$$;

create or replace function public.clear_group_check_in_when_declining()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.rsvp = 'no' then
    new.checked_in_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists group_member_decline_clears_check_in on public.group_ride_members;
create trigger group_member_decline_clears_check_in
before insert or update of rsvp on public.group_ride_members
for each row execute function public.clear_group_check_in_when_declining();

revoke all on function public.get_group_ride_operations(uuid) from public, anon, authenticated;
revoke all on function public.set_group_ride_check_in(uuid, boolean) from public, anon, authenticated;
revoke all on function public.post_group_ride_announcement(uuid, text) from public, anon, authenticated;
revoke all on function public.clear_group_check_in_when_declining() from public, anon, authenticated;

grant execute on function public.get_group_ride_operations(uuid) to anon, authenticated;
grant execute on function public.set_group_ride_check_in(uuid, boolean) to authenticated;
grant execute on function public.post_group_ride_announcement(uuid, text) to authenticated;

commit;
