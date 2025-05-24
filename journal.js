import supabase from './supabaseClient.js';

const momentsList = document.getElementById('journal-moments-list');
const galleryBtn = document.getElementById('gallery-view-btn');
const timelineBtn = document.getElementById('timeline-view-btn');

// Utility: Render an error message to the moments area
function renderError(message) {
  if (momentsList) {
    momentsList.innerHTML = `<div class="error-message">${message}</div>`;
  }
}

// Utility: Render a loading state
function renderLoading() {
  if (momentsList) {
    momentsList.innerHTML = `<div class="loading-message">Loading your moments...</div>`;
  }
}

// Utility: Render moments (accepts array of moment objects)
function renderMoments(momentArr = []) {
  if (!momentsList) return;

  if (!Array.isArray(momentArr) || momentArr.length === 0) {
    momentsList.innerHTML = `<em>No moments found yet. Start adding moments on your rides!</em>`;
    return;
  }

  // Document fragment for better performance with large lists
  const frag = document.createDocumentFragment();

  momentArr.forEach(m => {
    const div = document.createElement('div');
    div.className = 'moment-entry journal-moment-card';
    div.innerHTML = `
      <div class="journal-moment-head">
        <strong>${m.title ? m.title : 'Untitled Moment'}</strong>
        <span style="color:#64ffda;margin-left:1em;">${m.rideDate ? new Date(m.rideDate).toLocaleDateString() : ''}</span>
      </div>
      <div class="journal-moment-meta">
        <span>From <a href="index.html?ride=${m.rideId}" style="color:#00c6ff;text-decoration:underline;">${m.rideTitle || '(untitled ride)'}</a></span>
        ${typeof m.speed === 'number' ? `<span>• ${m.speed.toFixed(1)} km/h</span>` : ''}
        ${typeof m.elevation === 'number' ? `<span>• ${m.elevation.toFixed(0)} m</span>` : ''}
      </div>
      <div class="journal-moment-note">${m.note ? m.note : '<em>(No notes)</em>'}</div>
    `;
    frag.appendChild(div);
  });

  // Replace content at once for performance
  momentsList.innerHTML = '';
  momentsList.appendChild(frag);
}

// Utility: Toggle between Timeline and Gallery view
function setupViewToggle() {
  if (!galleryBtn || !timelineBtn || !momentsList) return;
  galleryBtn.addEventListener('click', () => {
    galleryBtn.classList.add('active');
    timelineBtn.classList.remove('active');
    momentsList.classList.add('gallery-view');
    galleryBtn.setAttribute('aria-pressed', 'true');
    timelineBtn.setAttribute('aria-pressed', 'false');
  });
  timelineBtn.addEventListener('click', () => {
    timelineBtn.classList.add('active');
    galleryBtn.classList.remove('active');
    momentsList.classList.remove('gallery-view');
    timelineBtn.setAttribute('aria-pressed', 'true');
    galleryBtn.setAttribute('aria-pressed', 'false');
  });
}

// Main app logic wrapped in IIFE for async/await
(async function main() {
  renderLoading();

  // 1. Check if user is logged in
  let user;
  try {
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData || !authData.user) {
      renderError('Please log in to view your Rider’s Journal.');
      return;
    }
    user = authData.user;
  } catch (e) {
    renderError('Unexpected authentication error. Please reload.');
    return;
  }

  // 2. Fetch rides and handle DB errors
  let rides;
  try {
    const { data, error } = await supabase
      .from('ride_logs')
      .select('id, title, ride_date, moments')
      .eq('user_id', user.id)
      .order('ride_date', { ascending: false });

    if (error || !Array.isArray(data)) {
      renderError('Failed to load your moments. Please try again later.');
      return;
    }
    rides = data;
  } catch (e) {
    renderError('Error fetching rides. Please check your network and try again.');
    return;
  }

  // 3. Flatten all moments, add ride info, filter bad/empty moments
  const allMoments = [];
  rides.forEach(ride => {
    if (Array.isArray(ride.moments)) {
      ride.moments.forEach((moment, idx) => {
        // Defensive: Only process objects
        if (moment && typeof moment === 'object') {
          allMoments.push({
            ...moment,
            rideId: ride.id,
            rideTitle: ride.title,
            rideDate: ride.ride_date,
            idx: idx
          });
        }
      });
    }
  });

  // 4. Sort by ride date (desc), then by moment idx (desc)
  allMoments.sort((a, b) => {
    const dateA = new Date(a.rideDate);
    const dateB = new Date(b.rideDate);
    if (dateA - dateB !== 0) return dateB - dateA;
    return (b.idx || 0) - (a.idx || 0);
  });

  // 5. Render all moments or empty state
  renderMoments(allMoments);

  // 6. Setup view toggles (once DOM is ready)
  setupViewToggle();

  // Optionally: Add future hooks for filtering/search here
})();

