document.addEventListener('DOMContentLoaded', async () => {
  const rideList = document.getElementById('ride-list');

  const {
    data: { user },
    error: userError
  } = await supabase.auth.getUser();

  if (userError || !user) {
    rideList.textContent = '⚠️ Please log in to view your dashboard.';
    return;
  }

  const { data, error } = await supabase
    .from('ride_logs')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });

  if (error) {
    rideList.textContent = '❌ Failed to load rides.';
    return;
  }

  if (!data.length) {
    rideList.textContent = 'No rides saved yet.';
    return;
  }

  rideList.innerHTML = data.map(ride => `
    <div class="ride-card">
      <h3>${ride.title}</h3>
      <p>📏 ${ride.distance_km.toFixed(1)} km</p>
      <p>🕒 ${ride.duration_min} min</p>
      <p>🧗 ${ride.elevation_m} m</p>
      <p>📅 ${new Date(ride.created_at).toLocaleString()}</p>
    </div>
  `).join('');
});

document.getElementById('logout-btn').addEventListener('click', async () => {
  await supabase.auth.signOut();
  window.location.href = 'index.html';
});
