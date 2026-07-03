-- ============================================================
-- Memory Lanes: Ride Coach skill storage - one-time setup
-- Run this in Supabase Dashboard -> SQL Editor -> New query
-- ============================================================
-- Stores a compact per-ride skill summary (scores, ride composition,
-- corner fingerprints) so the app can show skill trends over time and
-- recognise corners you have ridden before.

alter table ride_logs add column if not exists skills jsonb;

-- No new policies needed: owners already update their own rows, and
-- the shared-ride function (if installed) exposes rows via jsonb where
-- skills ride along harmlessly.
