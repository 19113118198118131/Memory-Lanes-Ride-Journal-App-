-- ============================================================
-- Memory Lanes: Route Planner — one-time setup
-- Run this in Supabase Dashboard -> SQL Editor -> New query
-- ============================================================

-- Planned routes: built on the "Plan a Route" page, road-snapped via OSRM.
-- Distinct from ride_logs (which stores *recorded* GPX rides).
create table if not exists planned_routes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  distance_km numeric,
  elevation_m numeric,
  waypoints jsonb not null,   -- the clicked waypoints, in order: [{lat, lng}, ...]
  route jsonb not null,       -- the dense road-snapped line: [[lat, lng], ...]
  created_at timestamptz not null default now()
);

create index if not exists planned_routes_user_id_idx on planned_routes (user_id);

alter table planned_routes enable row level security;

create policy "owners select own planned routes" on planned_routes
  for select using (auth.uid() = user_id);
create policy "owners insert own planned routes" on planned_routes
  for insert with check (auth.uid() = user_id);
create policy "owners update own planned routes" on planned_routes
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "owners delete own planned routes" on planned_routes
  for delete using (auth.uid() = user_id);
