-- ============================================================
-- Memory Lanes: AI Phase 0 - ride feedback + feature records
-- Run this in Supabase Dashboard -> SQL Editor -> New query
-- ============================================================

-- Folded onto ride_logs (like the existing skills jsonb) so one query returns
-- a ride's features and the rider's rating together - the recommender reads
-- exactly these two columns across the user's rides. Owner-only RLS on
-- ride_logs already governs them.
alter table ride_logs add column if not exists ai_features jsonb;
alter table ride_logs add column if not exists ai_version text;

-- Post-ride feedback:
-- { mood, enjoyment (1-5), wouldRepeat (bool), reasons:{likedCorners,...}, at }
alter table ride_logs add column if not exists feedback jsonb;
