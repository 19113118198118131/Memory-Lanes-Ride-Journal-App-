-- Memory Lanes: secure notification preferences, APNs devices and group-event outbox.
-- Delivery is performed by the `deliver-group-notifications` Edge Function.

begin;

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  event_updates boolean not null default true,
  rsvp_updates boolean not null default true,
  ride_reminders boolean not null default true,
  quiet_hours boolean not null default true,
  timezone text not null default 'UTC',
  updated_at timestamptz not null default now()
);

create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  environment text not null check (environment in ('development', 'production')),
  app_version text,
  timezone text not null default 'UTC',
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_devices_token_length check (char_length(token) between 32 and 512)
);

create index if not exists push_devices_active_user_idx
  on public.push_devices (user_id)
  where is_active = true;

create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  group_ride_id uuid references public.group_rides(id) on delete cascade,
  kind text not null check (kind in ('group_rsvp', 'group_updated', 'group_cancelled', 'ride_reminder')),
  title text not null,
  body text not null,
  deep_link text,
  status text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed', 'skipped')),
  scheduled_for timestamptz not null default now(),
  attempts integer not null default 0,
  last_error text,
  sent_at timestamptz,
  dedupe_key text not null unique,
  created_at timestamptz not null default now()
);

create index if not exists notification_outbox_delivery_idx
  on public.notification_outbox (status, scheduled_for)
  where status in ('pending', 'failed');
create index if not exists notification_outbox_recipient_idx
  on public.notification_outbox (recipient_id);
create index if not exists notification_outbox_group_ride_idx
  on public.notification_outbox (group_ride_id)
  where group_ride_id is not null;

alter table public.notification_preferences enable row level security;
alter table public.push_devices enable row level security;
alter table public.notification_outbox enable row level security;

drop policy if exists "users own notification preferences" on public.notification_preferences;
create policy "users own notification preferences" on public.notification_preferences
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "users own push devices" on public.push_devices;
create policy "users own push devices" on public.push_devices
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "clients cannot access notification outbox" on public.notification_outbox;
create policy "clients cannot access notification outbox" on public.notification_outbox
  for all to authenticated
  using (false)
  with check (false);

revoke all on public.notification_preferences from public, anon, authenticated;
revoke all on public.push_devices from public, anon, authenticated;
revoke all on public.notification_outbox from public, anon, authenticated;

create or replace function public.get_notification_preferences()
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  result jsonb;
begin
  if uid is null then
    return null;
  end if;
  select jsonb_build_object(
    'event_updates', coalesce(p.event_updates, true),
    'rsvp_updates', coalesce(p.rsvp_updates, true),
    'ride_reminders', coalesce(p.ride_reminders, true),
    'quiet_hours', coalesce(p.quiet_hours, true),
    'timezone', coalesce(p.timezone, 'UTC'),
    'updated_at', p.updated_at
  ) into result
  from (select uid as user_id) u
  left join public.notification_preferences p on p.user_id = u.user_id;
  return result;
end;
$$;

create or replace function public.set_notification_preferences(
  p_event_updates boolean,
  p_rsvp_updates boolean,
  p_ride_reminders boolean,
  p_quiet_hours boolean,
  p_timezone text
)
returns jsonb
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    return null;
  end if;
  insert into public.notification_preferences (
    user_id, event_updates, rsvp_updates, ride_reminders, quiet_hours, timezone, updated_at
  ) values (
    uid, p_event_updates, p_rsvp_updates, p_ride_reminders, p_quiet_hours,
    left(coalesce(nullif(trim(p_timezone), ''), 'UTC'), 100), now()
  )
  on conflict (user_id) do update set
    event_updates = excluded.event_updates,
    rsvp_updates = excluded.rsvp_updates,
    ride_reminders = excluded.ride_reminders,
    quiet_hours = excluded.quiet_hours,
    timezone = excluded.timezone,
    updated_at = now();
  return public.get_notification_preferences();
end;
$$;

create or replace function public.register_push_device(
  p_device_token text,
  p_push_environment text,
  p_app_version text,
  p_timezone text
)
returns uuid
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  device_id uuid;
  clean_token text := lower(trim(p_device_token));
begin
  if uid is null then
    return null;
  end if;
  if p_push_environment not in ('development', 'production') then
    raise exception 'Unsupported push environment.' using errcode = 'P0001';
  end if;
  if char_length(clean_token) < 32 or char_length(clean_token) > 512
     or clean_token !~ '^[0-9a-f]+$' then
    raise exception 'Invalid APNs device token.' using errcode = 'P0001';
  end if;

  insert into public.notification_preferences (user_id, timezone, updated_at)
  values (uid, left(coalesce(nullif(trim(p_timezone), ''), 'UTC'), 100), now())
  on conflict (user_id) do update set
    timezone = excluded.timezone,
    updated_at = now();

  insert into public.push_devices (
    user_id, token, environment, app_version, timezone, is_active, last_seen_at, updated_at
  ) values (
    uid, clean_token, p_push_environment, left(p_app_version, 40),
    left(coalesce(nullif(trim(p_timezone), ''), 'UTC'), 100), true, now(), now()
  )
  on conflict (token) do update set
    user_id = uid,
    environment = excluded.environment,
    app_version = excluded.app_version,
    timezone = excluded.timezone,
    is_active = true,
    last_seen_at = now(),
    updated_at = now()
  returning id into device_id;
  return device_id;
end;
$$;

create or replace function public.remove_push_device(p_device_token text)
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return false;
  end if;
  update public.push_devices d
  set is_active = false, updated_at = now()
  where d.token = lower(trim(p_device_token)) and d.user_id = (select auth.uid());
  return found;
end;
$$;

create or replace function public.enqueue_group_rsvp_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  ride public.group_rides%rowtype;
  rider_name text;
  answer text;
begin
  if tg_op = 'UPDATE' and old.rsvp = new.rsvp then
    return new;
  end if;
  select * into ride from public.group_rides where id = new.group_ride_id;
  if ride.owner_id = new.user_id or ride.status <> 'scheduled' then
    return new;
  end if;
  if not coalesce((select p.rsvp_updates from public.notification_preferences p where p.user_id = ride.owner_id), true) then
    return new;
  end if;
  select coalesce(nullif(trim(p.display_name), ''), 'A rider') into rider_name
  from public.profiles p where p.user_id = new.user_id;
  rider_name := coalesce(rider_name, 'A rider');
  answer := case new.rsvp when 'going' then 'is riding' when 'maybe' then 'might join' else 'cannot make it' end;
  insert into public.notification_outbox (
    recipient_id, group_ride_id, kind, title, body, deep_link, dedupe_key
  ) values (
    ride.owner_id, ride.id, 'group_rsvp', ride.title,
    rider_name || ' ' || answer || '.',
    'memorylanes://group/' || ride.share_token::text,
    'rsvp:' || ride.id::text || ':' || new.user_id::text || ':' || new.rsvp || ':' || gen_random_uuid()::text
  );
  return new;
end;
$$;

drop trigger if exists group_ride_member_notification on public.group_ride_members;
create trigger group_ride_member_notification
after insert or update of rsvp on public.group_ride_members
for each row execute function public.enqueue_group_rsvp_notification();

create or replace function public.enqueue_group_update_notifications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  notification_kind text;
  notification_title text;
  notification_body text;
begin
  if new.title is not distinct from old.title
     and new.details is not distinct from old.details
     and new.meet_time is not distinct from old.meet_time
     and new.meet_point is not distinct from old.meet_point
     and new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'cancelled' and old.status is distinct from new.status then
    notification_kind := 'group_cancelled';
    notification_title := 'Ride cancelled';
    notification_body := new.title || ' has been cancelled by the organiser.';
  else
    notification_kind := 'group_updated';
    notification_title := 'Ride updated';
    notification_body := new.title || ' has new event details.';
  end if;

  insert into public.notification_outbox (
    recipient_id, group_ride_id, kind, title, body, deep_link, dedupe_key
  )
  select m.user_id, new.id, notification_kind, notification_title, notification_body,
    'memorylanes://group/' || new.share_token::text,
    'update:' || new.id::text || ':' || m.user_id::text || ':' || gen_random_uuid()::text
  from public.group_ride_members m
  where m.group_ride_id = new.id
    and m.user_id <> new.owner_id
    and m.rsvp <> 'no'
    and coalesce((select p.event_updates from public.notification_preferences p where p.user_id = m.user_id), true);
  return new;
end;
$$;

drop trigger if exists group_ride_update_notification on public.group_rides;
create trigger group_ride_update_notification
after update of title, details, meet_time, meet_point, status on public.group_rides
for each row execute function public.enqueue_group_update_notifications();

create or replace function public.enqueue_due_group_ride_reminders()
returns integer
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  inserted_count integer;
begin
  insert into public.notification_outbox (
    recipient_id, group_ride_id, kind, title, body, deep_link, scheduled_for, dedupe_key
  )
  select m.user_id, g.id, 'ride_reminder', 'Ride starts in one hour',
    g.title || case when g.meet_point is not null then ' meets at ' || g.meet_point || '.' else ' is coming up.' end,
    'memorylanes://group/' || g.share_token::text, now(),
    'reminder-60:' || g.id::text || ':' || m.user_id::text
  from public.group_rides g
  join public.group_ride_members m on m.group_ride_id = g.id
  where g.status = 'scheduled'
    and g.meet_time > now() + interval '55 minutes'
    and g.meet_time <= now() + interval '65 minutes'
    and m.rsvp in ('going', 'maybe')
    and coalesce((select p.ride_reminders from public.notification_preferences p where p.user_id = m.user_id), true)
  on conflict (dedupe_key) do nothing;
  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on function public.get_notification_preferences() from public, anon, authenticated;
revoke all on function public.set_notification_preferences(boolean, boolean, boolean, boolean, text) from public, anon, authenticated;
revoke all on function public.register_push_device(text, text, text, text) from public, anon, authenticated;
revoke all on function public.remove_push_device(text) from public, anon, authenticated;
revoke all on function public.enqueue_group_rsvp_notification() from public, anon, authenticated;
revoke all on function public.enqueue_group_update_notifications() from public, anon, authenticated;
revoke all on function public.enqueue_due_group_ride_reminders() from public, anon, authenticated;

grant execute on function public.get_notification_preferences() to authenticated;
grant execute on function public.set_notification_preferences(boolean, boolean, boolean, boolean, text) to authenticated;
grant execute on function public.register_push_device(text, text, text, text) to authenticated;
grant execute on function public.remove_push_device(text) to authenticated;
grant execute on function public.enqueue_due_group_ride_reminders() to service_role;

commit;
