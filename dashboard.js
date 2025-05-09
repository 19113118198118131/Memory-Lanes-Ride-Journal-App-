import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// Supabase config
const SUPABASE_URL = 'https://vodujxiwkpxaxaqnwkdd.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZvZHVqeGl3a3B4YXhhcW53a2RkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY3NTgwOTQsImV4cCI6MjA2MjMzNDA5NH0.k4NeZ3dgqe1QQeXmkmgThp-X_PwOHPHLAQErg3hrPok'; // Replace with your real anon key
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// DOM references
const rideList = document.getElementById('ride-list');
const logoutBtn = document.getElementById('logout-btn');

// Auto-execute async init
(async () => {
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    window.location.href = 'index.html';
    return;
  }

  // Load rides for this user
  const { data: rides, error: fetchError } = await supabase
    .from('ride_logs')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });

  rideList.innerHTML = ''; // Clear "Loading..."

  if (fetchError) {
    rideList.textContent = '❌ Failed to load rides.';
    return;
  }

  if (!rides.length) {
    rideList.textContent = 'No rides found.';
    return;
  }

  // Render ride cards
  rides.forEach(ride => {
    const item = document.createElement('div');
    item.className = 'ride-entry';
    item.innerHTML = `
      <div class="ride-card">
        <div class="ride-title">${ride.title}</div>
        <div class="ride-details">
          <span>📍 ${ride.distance_km.toFixed(1)} km</span>
          <span>⏱ ${ride.duration_min} min</span>
          <span>⛰️ ${ride.elevation_m} m</span>
          <span>📅 ${new Date(ride.created_at).toLocaleDateString()}</span>
        </div>
      </div>
    `;
    item.style.cursor = 'pointer';
    item.dataset.rideId = ride.id;
    item.addEventListener('click', () => {
      localStorage.setItem('selectedRideId', ride.id);
      window.location.href = 'index.html';
    });
    rideList.appendChild(item);
  });
})();

// Logout button
logoutBtn.addEventListener('click', async () => {
  await supabase.auth.signOut();
  window.location.href = 'index.html';
});
