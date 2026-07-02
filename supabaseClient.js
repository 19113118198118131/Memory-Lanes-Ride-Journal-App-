// supabaseClient.js
//
// NOTE: The anon key below is designed to be public, BUT that is only safe if
// Row Level Security (RLS) is enabled on the `ride_logs` table and the
// `gpx-files` storage bucket. Recommended policies:
//   ride_logs:  SELECT/INSERT/UPDATE/DELETE only where user_id = auth.uid()
//   gpx-files:  users may only write/delete within a folder named after their uid
// Verify these in the Supabase dashboard (Auth > Policies) before sharing the app.
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL     = 'https://vodujxiwkpxaxaqnwkdd.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZvZHVqeGl3a3B4YXhhcW53a2RkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY3NTgwOTQsImV4cCI6MjA2MjMzNDA5NH0.k4NeZ3dgqe1QQeXmkmgThp-X_PwOHPHLAQErg3hrPok'; // anon key

// Export a single Supabase client instance
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
export default supabase;
