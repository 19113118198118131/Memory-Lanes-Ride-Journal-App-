-- ============================================================
-- Memory Lanes: Public Share Links — one-time setup
-- Run this in Supabase Dashboard -> SQL Editor -> New query
-- ============================================================

-- 1) Add sharing columns to ride_logs
alter table ride_logs add column if not exists is_public boolean not null default false;
alter table ride_logs add column if not exists share_token uuid not null default gen_random_uuid();
create unique index if not exists ride_logs_share_token_idx on ride_logs (share_token);

-- 2) Read function for shared rides.
--    SECURITY DEFINER lets anonymous visitors read exactly ONE ride,
--    only if they know its secret token AND the owner marked it public.
--    This avoids adding a broad SELECT policy, so public rides can
--    never be listed/enumerated — the token is the key.
--    user_id is stripped from the result so owners stay anonymous.
create or replace function get_shared_ride(token uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select to_jsonb(r.*) - 'user_id'
  from ride_logs r
  where r.share_token = token
    and r.is_public = true
  limit 1;
$$;

revoke all on function get_shared_ride(uuid) from public;
grant execute on function get_shared_ride(uuid) to anon, authenticated;

-- 3) Owners toggle sharing via UPDATE on their own rows.
--    If you already have an owner update policy like
--    "user_id = auth.uid()", nothing more is needed.
--    If updates fail, create one:
-- create policy "owners update own rides" on ride_logs
--   for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- NOTE on GPX files: the app already reads GPX via public bucket URLs
-- (getPublicUrl), so shared viewers can load routes with no extra setup.
