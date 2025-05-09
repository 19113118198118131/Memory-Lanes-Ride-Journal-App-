import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// Supabase config
import supabase from './supabaseClient.js';

// DOM references
const rideList = document.getElementById('ride-list');
const logoutBtn = document.getElementById('logout-btn');

// Main init
(async () => {
  // Ensure user is authenticated
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    window.location.href = 'index.html';
    return;
  }

  // Fetch rides for this user
  const { data: rides, error: fetchError } = await supabase
    .from('ride_logs')
    .select('id, title, distance_km, duration_min, elevation_m, created_at')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });

  // Clear loading state
  rideList.innerHTML = '';

  if (fetchError) {
    rideList.textContent = '❌ Failed to load rides.';
    return;
  }

  if (!rides.length) {
    rideList.textContent = 'No rides found.';
    return;
  }

  // Render each ride entry
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
    item.addEventListener('click', () => {
      localStorage.setItem('selectedRideId', ride.id);
      window.location.href = 'index.html';
    });
    rideList.appendChild(item);
  });
})();

// Logout
logoutBtn.addEventListener('click', async () => {
  await supabase.auth.signOut();
  window.location.href = 'index.html';
});
