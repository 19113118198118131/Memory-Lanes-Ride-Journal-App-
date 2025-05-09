// script.js

// Import Supabase as module
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// Initialize Supabase client and expose globally
const SUPABASE_URL     = 'https://vodujxiwkpxaxaqnwkdd.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZvZHVqeGl3a3B4YXhhcW53a2RkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY3NTgwOTQsImV4cCI6MjA2MjMzNDA5NH0.k4NeZ3dgqe1QQeXmkmgThp-X_PwOHPHLAQErg3hrPok';
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.supabase = supabase;

console.log('script.js loaded');
window.updatePlayback = null;

// Preload block for dashboard-to-viewer flow
(async () => {
  // Ensure session is loaded
  const { data: { session }, error: sessionErr } = await supabase.auth.getSession();
  if (sessionErr) console.warn('Session error:', sessionErr);
  console.log('🔐 session =', session);

  const urlParams     = new URLSearchParams(window.location.search);
  const preloadRideId = urlParams.get('ride');
  console.log('▶ script.js sees rideId=', preloadRideId);

  if (!preloadRideId) return;

  // Hide login/upload UI, show ride-viewer UI
  document.getElementById('auth-section').style.display        = 'none';
  document.getElementById('upload-section').style.display      = 'none';
  document.getElementById('save-ride-form').style.display      = 'none';
  document.getElementById('map-section').style.display         = 'block';
  document.getElementById('summary-section').style.display     = 'block';
  document.getElementById('timeline').style.display            = 'block';
  document.getElementById('analytics-container').style.display = 'block';

  // Fetch ride metadata including GPX path
  const { data: rides, error } = await supabase
    .from('ride_logs')
    .select('id, title, gpx_path, distance_km, duration_min, elevation_m')
    .eq('id', preloadRideId)
    .single();

  if (error || !rides) {
    console.error('Error loading ride:', error);
    return;
  }
  const ride = rides;
  console.log('✔ Preloading ride:', ride);

  // Get public URL for GPX file
  const { data: storageData, error: urlErr } = supabase
    .storage
    .from('gpx-files')
    .getPublicUrl(ride.gpx_path);

  if (urlErr) {
    console.error('Error getting GPX URL:', urlErr);
  } else {
    loadGPX(storageData.publicUrl);
  }

  // Populate save form
  document.getElementById('ride-title').value = ride.title;
  document.getElementById('save-ride-form').style.display = 'block';

})();

// DOMContentLoaded: legacy logic and UI setup
document.addEventListener('DOMContentLoaded', async () => {
  // Legacy localStorage fallback
  const selectedRideId = localStorage.getItem('selectedRideId');
  if (selectedRideId) {
    localStorage.removeItem('selectedRideId');
    const { data, error } = await supabase
      .from('ride_logs')
      .select('*')
      .eq('id', selectedRideId)
      .single();
    if (data && !error) {
      document.getElementById('ride-title').value = data.title;
      document.getElementById('save-ride-form').style.display = 'block';
      document.getElementById('distance').textContent  = `${data.distance_km.toFixed(2)} km`;
      document.getElementById('duration').textContent  = `${data.duration_min} min`;
      document.getElementById('elevation').textContent = `${data.elevation_m} m`;
    }
  }

  // Hide save form if not logged in
  supabase.auth.getUser().then(({ data:{ user } }) => {
    if (!user) document.getElementById('save-ride-form').style.display = 'none';
  });

  // Clean up URL hash after signup or magic link
  if (window.location.hash.includes('type=signup') || window.location.hash.includes('access_token')) {
    history.replaceState({}, document.title, window.location.pathname);
  }

  // Auth handlers
  document.getElementById('login-btn').addEventListener('click', async () => {
    const email    = document.getElementById('auth-email').value;
    const password = document.getElementById('auth-password').value;
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    const statusEl = document.getElementById('auth-status');
    statusEl.textContent = error
      ? 'Login failed: ' + error.message
      : 'Login successful! Redirecting…';
    if (!error) setTimeout(() => window.location.href = 'dashboard.html', 1000);
  });

  document.getElementById('signup-btn').addEventListener('click', async () => {
    const email    = document.getElementById('auth-email').value;
    const password = document.getElementById('auth-password').value;
    const { error } = await supabase.auth.signUp({ email, password });
    document.getElementById('auth-status').textContent =
      error ? 'Signup failed: ' + error.message : 'Signup successful! Check your email.';
  });

  // Leaflet map initialization
  const map = L.map('map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

  // Globals & DOM refs
  let points = [], marker = null, trailPolyline = null;
  let elevationChart = null, cumulativeDistance = [], speedData = [], breakPoints = [];
  let playInterval = null, fracIndex = 0, speedHighlightLayer = null;
  const FRAME_DELAY_MS = 50;
  const distanceEl  = document.getElementById('distance');
  const durationEl  = document.getElementById('duration');
  const rideTimeEl  = document.getElementById('ride-time');
  const elevationEl = document.getElementById('elevation');
  const slider      = document.getElementById('replay-slider');
  const playBtn     = document.getElementById('play-replay');
  const summaryBtn  = document.getElementById('download-summary');
  const videoBtn    = document.getElementById('export-video');
  const speedSel    = document.getElementById('playback-speed');
  const uploadInput = document.getElementById('gpx-upload');

  [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = true);

  // Speed filter setup
  const speedBins = [
    { label: '50–80',   min: 50,  max:  80 },
    { label: '80–100',  min: 80,  max: 100 },
    { label: '100–120', min: 100, max: 120 },
    { label: '120–160', min: 120, max: 160 },
    { label: '160–200', min: 160, max: 200 },
    { label: '200+',    min: 200, max: Infinity }
  ];

  function renderSpeedFilter() {
    const container = document.getElementById('speed-bins');
    container.innerHTML = '';
    speedBins.forEach((bin, i) => {
      const btn = document.createElement('button');
      btn.textContent = bin.label;
      btn.classList.add('speed-bin-btn');
      btn.dataset.index = i;
      btn.addEventListener('click', () => highlightSpeedBin(i));
      container.appendChild(btn);
    });
  }

  function highlightSpeedBin(binIndex) {
    // ... existing highlight logic ...
  }

  function updatePlayback(idx) {
    // ... existing playback logic ...
  }
  window.updatePlayback = updatePlayback;

  function setupChart() {
    // ... existing Chart.js setup ...
  }

  // GPX load & parsing
  uploadInput.addEventListener('change', e => {
    console.log('⚙️ upload handler fired, loadGPX is', typeof loadGPX);
    const file = e.target.files[0];
    if (!file) return;
    // reset any previous playback
    if (playInterval) clearInterval(playInterval);
    if (marker) map.removeLayer(marker);
    if (trailPolyline) map.removeLayer(trailPolyline);
    points = []; breakPoints = [];

    const reader = new FileReader();
    reader.onload = ev => {
      const xml = new DOMParser().parseFromString(ev.target.result, 'application/xml');
      const trkpts = Array.from(xml.getElementsByTagName('trkpt')).map(tp => ({
        lat:+tp.getAttribute('lat'),
        lng:+tp.getAttribute('lon'),
        ele:+tp.getElementsByTagName('ele')[0]?.textContent||0,
        time:new Date(tp.getElementsByTagName('time')[0]?.textContent)
      })).filter(p => p.lat && p.lng && p.time instanceof Date);
      if (!trkpts.length) return alert('No valid trackpoints found');

      // (existing decimation, distance, speed, elevation calculations…)
      // build points[], cumulativeDistance[], speedData[], breakPoints[]…
      // then:
      trailPolyline = L.polyline(points.map(p=>[p.lat,p.lng]),{color:'#007bff',weight:3,opacity:0.7}).addTo(map).bringToBack();
      map.fitBounds(trailPolyline.getBounds(),{padding:[30,30],animate:false});
      setupChart();
      renderSpeedFilter();
      [slider,playBtn,summaryBtn,videoBtn,speedSel].forEach(el=>el.disabled=false);
      if(window.Analytics) Analytics.initAnalytics(points,speedData,cumulativeDistance);
    };
    reader.readAsText(file);
  });


  // Play/Pause, slider, summary, save handlers
  playBtn.addEventListener('click', () => { /* ... */ });
  slider.addEventListener('input', () => { /* ... */ });
  summaryBtn.addEventListener('click', () => { /* ... */ });
  document.getElementById('save-ride-btn').addEventListener('click', async () => {
    const file = uploadInput.files[0];
    if (!file) return;
    const user = (await supabase.auth.getUser()).data.user;
    if (!user) {
      document.getElementById('save-status').textContent = 'User not logged in!';
      return;
    }
    const filename = `${user.id}/${Date.now()}-${file.name}`;

    // 1) Upload to Storage
    const { error: uploadErr } = await supabase
      .storage.from('gpx-files')
      .upload(filename, file);
    if (uploadErr) {
      return document.getElementById('save-status').textContent =
        '❌ Upload failed: ' + uploadErr.message;
    }

    // 2) Save metadata + path in ride_logs
    const { data: insertData, error: insertErr } = await supabase
      .from('ride_logs')
      .insert([{ user_id: user.id, title: document.getElementById('ride-title').value, distance_km: parseFloat(distanceEl.textContent), duration_min: parseInt(durationEl.textContent), elevation_m: parseInt(elevationEl.textContent), gpx_path: filename }])
      .select();
    if (insertErr) {
      return document.getElementById('save-status').textContent =
        '❌ Save failed: ' + insertErr.message;
    }

    document.getElementById('save-status').textContent = '✅ Ride saved!';
  });
});
