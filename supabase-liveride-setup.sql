-- ============================================================
-- Memory Lanes: Start Ride / Follow / Compare — one-time setup
-- Run this in Supabase Dashboard -> SQL Editor -> New query
-- Requires supabase-routeplanner-setup.sql to have been run first.
-- ============================================================

-- Links a recorded ride back to the planned route it was following,
-- so the ride page can overlay planned vs. actual and show a match stat.
alter table ride_logs add column if not exists planned_route_id uuid references planned_routes(id) on delete set null;

create index if not exists ride_logs_planned_route_id_idx on ride_logs (planned_route_id);
