import supabase from './supabaseClient.js';

const momentsList = document.getElementById('journal-moments-list');

(async () => {
  // Get logged-in user
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    momentsList.textContent = 'Please login to view your Rider’s Journal.';
    return;
  }

  // Fetch all rides for this user
  const { data: rides, error } = await supabase
    .from('ride_logs')
    .select('id, title, ride_date, moments')
    .eq('user_id', user.id)
    .order('ride_date', { ascending: false });

  if (error || !rides) {
    momentsList.textContent = 'Failed to load moments. Please try again later.';
    return;
  }

  // Flatten all moments, attach ride info
  let allMoments = [];
  rides.forEach(ride => {
    if (Array.isArray(ride.moments)) {
      ride.moments.forEach(moment => {
        allMoments.push({
          ...moment,
          rideId: ride.id,
          rideTitle: ride.title,
          rideDate: ride.ride_date
        });
      });
    }
  });

  // Sort by moment (ride date + moment idx)
  allMoments.sort((a, b) => {
    const dateA = new Date(a.rideDate);
    const dateB = new Date(b.rideDate);
    if (dateA - dateB !== 0) return dateB - dateA; // Descending date
    return (b.idx || 0) - (a.idx || 0); // Newest moment first if same ride
  });

  if (allMoments.length === 0) {
    momentsList.innerHTML = `<em>No moments found yet. Start adding moments on your rides!</em>`;
    return;
  }

  // Render moments
  momentsList.innerHTML = '';
  allMoments.forEach(m => {
    const div = document.createElement('div');
    div.className = 'moment-entry journal-moment-card';
    div.innerHTML = `
      <div class="journal-moment-head">
        <strong>${m.title ? m.title : 'Untitled Moment'}</strong>
        <span style="color:#64ffda;margin-left:1em;">${new Date(m.rideDate).toLocaleDateString()}</span>
      </div>
      <div class="journal-moment-meta">
        <span>From <a href="index.html?ride=${m.rideId}" style="color:#00c6ff;text-decoration:underline;">${m.rideTitle || '(untitled ride)'}</a></span>
        ${m.speed ? `<span>• ${m.speed.toFixed(1)} km/h</span>` : ''}
        ${m.elevation ? `<span>• ${m.elevation.toFixed(0)} m</span>` : ''}
      </div>
      <div class="journal-moment-note">${m.note ? m.note : '<em>(No notes)</em>'}</div>
    `;
    momentsList.appendChild(div);
  });
})();
