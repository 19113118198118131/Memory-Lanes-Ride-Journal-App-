-- ============================================================
-- Memory Lanes: Shared Route Library / Invite a Rider — one-time setup
-- Run this in Supabase Dashboard -> SQL Editor -> New query
-- (Mirrors the ride-sharing pattern in supabase-share-setup.sql.)
-- ============================================================

-- 1) Add sharing columns to planned_routes
alter table planned_routes add column if not exists is_public boolean not null default false;
alter table planned_routes add column if not exists share_token uuid not null default gen_random_uuid();
create unique index if not exists planned_routes_share_token_idx on planned_routes (share_token);

-- 2) Read function for shared routes.
--    SECURITY DEFINER lets anonymous visitors read exactly ONE route,
--    only if they know its secret token AND the owner marked it public.
--    No broad SELECT policy is added, so shared routes can never be
--    listed/enumerated — the token is the key.
--    user_id is stripped from the result so owners stay anonymous.
create or replace function get_shared_route(token uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select to_jsonb(r.*) - 'user_id'
  from planned_routes r
  where r.share_token = token
    and r.is_public = true
  limit 1;
$$;

revoke all on function get_shared_route(uuid) from public;
grant execute on function get_shared_route(uuid) to anon, authenticated;

-- 3) Owners toggle sharing via UPDATE on their own rows — the
--    "owners update own planned routes" policy from
--    supabase-routeplanner-setup.sql already covers this.
