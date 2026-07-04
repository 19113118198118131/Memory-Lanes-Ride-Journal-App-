// supabaseClient.js
//
// Project: Memory-Lanes-Ride-Journal (ubuhaxnuhaacvxzezabd, ap-southeast-2)
// The anon key below is public by design; safety comes from Row Level
// Security, which is enabled with owner-only policies on ride_logs and
// per-user-folder policies on the gpx-files bucket (set up 2026-07-04).
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL      = 'https://ubuhaxnuhaacvxzezabd.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVidWhheG51aGFhY3Z4emV6YWJkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMTQxNzMsImV4cCI6MjA5ODY5MDE3M30.J3EgkfHB7oumm42pCQex-aVD7sqwhGAWM0_bxuc0P_Y';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
export default supabase;
