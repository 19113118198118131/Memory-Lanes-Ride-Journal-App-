-- Serialise final-place claims and keep capacity internally consistent.

begin;

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

revoke all on function public.enforce_group_ride_capacity() from public, anon, authenticated;
revoke all on function public.rsvp_group_ride(uuid, text) from public, anon, authenticated;
grant execute on function public.rsvp_group_ride(uuid, text) to authenticated;

commit;
