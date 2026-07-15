-- Social production follow-up found by the Supabase security/performance audit.
-- Keep public object URLs working while preventing bucket-wide file listing,
-- and retire the anonymous web-era live-position RPC.

begin;

drop policy if exists "public read gpx" on storage.objects;

create index if not exists group_rides_route_id_idx
  on public.group_rides (route_id);

revoke execute on function public.get_live_riders(uuid) from anon;

commit;
