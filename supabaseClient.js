// supabaseClient.js
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL     = 'https://vodujxiwkpxaxaqnwkdd.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZvZHVqeGl3a3B4YXhhcW53a2RkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY3NTgwOTQsImV4cCI6MjA2MjMzNDA5NH0.k4NeZ3dgqe1QQeXmkmgThp-X_PwOHPHLAQErg3hrPok'; // anon key

// Export a single Supabase client instance
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
export default supabase;
