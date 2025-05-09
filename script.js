// 1) Imports & Supabase init (must be at the very top)
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
const SUPABASE_URL     = 'https://vodujxiwkpxaxaqnwkdd.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCe...';
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.supabase = supabase;

// 2) Globals
console.log('script.js loaded');
window.updatePlayback = null;

// 3) Preload-from-URL block
;(async () => {
  const params = new URLSearchParams(window.location.search);
  const rideId = params.get('ride');
  if (!rideId) return;

  // Hide auth & upload UI, show ride & map sections
  document.getElementById('auth-section').style.display      = 'none';
  document.getElementById('upload-section').style.display    = 'none';
  document.getElementById('save-ride-form').style.display    = 'block';
  document.getElementById('map-section').style.display       = 'block';
  document.getElementById('summary-section').style.display   = 'block';
  document.getElementById('timeline').style.display          = 'block';
  document.getElementById('analytics-container').style.display = 'block';

  try {
    // Fetch ride metadata
    const { data: ride, error } = await supabase
      .from('ride_logs')
      .select('gpx_path, title')
      .eq('id', rideId)
      .single();
    if (error) throw error;

    // Populate form & load GPX
    document.getElementById('ride-title').value = ride.title;
    const { data: { publicUrl }, error: urlErr } = supabase
      .storage
      .from('gpx-files')
      .getPublicUrl(ride.gpx_path);
    if (urlErr) throw urlErr;

    loadGPX(publicUrl);
  } catch (e) {
    console.error('⚠️ preload failed:', e);
  }
})();

// 4) DOMContentLoaded and UI setup
document.addEventListener('DOMContentLoaded', async () => {
  // 5) Initial auth check to gate UI
  const { data: { user } } = await supabase.auth.getUser();
  if (user) {
    document.getElementById('auth-section').style.display   = 'none';
    document.getElementById('upload-section').style.display = 'block';
  } else {
    document.getElementById('upload-section').style.display    = 'none';
    document.getElementById('map-section').style.display       = 'none';
    document.getElementById('summary-section').style.display   = 'none';
    document.getElementById('timeline').style.display          = 'none';
    document.getElementById('analytics-container').style.display = 'none';
  }

  // 4a) Handle ride restored via selectedRideId
  const selectedRideId = localStorage.getItem('selectedRideId');
  if (selectedRideId) {
    localStorage.removeItem('selectedRideId');
    const { data, error } = await supabase
      .from('ride_logs')
      .select('*')
      .eq('id', selectedRideId)
      .single();
    if (data) {
      document.getElementById('ride-title').value = data.title;
      document.getElementById('save-ride-form').style.display = 'block';
      document.getElementById('distance').textContent = `${data.distance_km.toFixed(2)} km`;
      document.getElementById('duration').textContent = `${data.duration_min} min`;
      document.getElementById('elevation').textContent = `${data.elevation_m} m`;
    }
  }

  // 4b) Handle email confirmation hash
  if (window.location.hash.includes('type=signup')) {
    document.getElementById('auth-status').textContent =
      '✅ Email confirmed! Please log in now.';
    history.replaceState({}, document.title, window.location.pathname);
  }
  if (window.location.hash.includes('access_token')) {
    history.replaceState({}, document.title, window.location.pathname);
  }

  // 6) Login button
  document.getElementById('login-btn').addEventListener('click', async () => {
    const email = document.getElementById('auth-email').value;
    const password = document.getElementById('auth-password').value;
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    const statusEl = document.getElementById('auth-status');
    if (error) {
      statusEl.textContent = 'Login failed: ' + error.message;
    } else {
      statusEl.textContent = 'Login successful! Redirecting…';
      setTimeout(() => window.location.href = 'dashboard.html', 1000);
    }
  });

  // 7) Signup button
  document.getElementById('signup-btn').addEventListener('click', async () => {
    const email = document.getElementById('auth-email').value;
    const password = document.getElementById('auth-password').value;
    const { error } = await supabase.auth.signUp({ email, password });
    const statusEl = document.getElementById('auth-status');
    statusEl.textContent = error
      ? 'Signup failed: ' + error.message
      : 'Signup successful! Please check your email.';
  });

  // — Leaflet map setup —
  const map = L.map('map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

  // — Globals & DOM refs —
  let points = [], marker = null, trailPolyline = null, elevationChart = null;
  let cumulativeDistance = [], speedData = [], breakPoints = [], playInterval = null;
  let fracIndex = 0, speedHighlightLayer = null, selectedSpeedBins = new Set(), accelData = [];

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

  // — Speed‐filter bins & UI —
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
    const btn = document.querySelector(`#speed-bins .speed-bin-btn[data-index="${binIndex}"]`);
    const isActive = selectedSpeedBins.has(binIndex);
    if (isActive) { selectedSpeedBins.delete(binIndex); btn.classList.remove('active'); }
    else        { selectedSpeedBins.add(binIndex); btn.classList.add('active'); }

    if (speedHighlightLayer) {
      map.removeLayer(speedHighlightLayer);
      speedHighlightLayer = null;
    }
    if (selectedSpeedBins.size === 0) {
      renderAccelChart(accelData, cumulativeDistance, speedData, [], speedBins);
      return;
    }

    const segments = [];
    for (let i = 1; i < points.length; i++) {
      const s = speedData[i];
      for (let binIdx of selectedSpeedBins) {
        const { min, max } = speedBins[binIdx];
        if (s >= min && s < max) {
          segments.push([[points[i-1].lat, points[i-1].lng], [points[i].lat, points[i].lng]]);
          break;
        }
      }
    }

    speedHighlightLayer = L.layerGroup(
      segments.map(seg => {
        const pl = L.polyline(seg, { weight: 5, opacity: 0.8 });
        pl.on('add', () => { if (pl._path) pl._path.classList.add('pulse-line'); });
        return pl;
      })
    ).addTo(map);

    renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
  }

  function updatePlayback(idx) {
    const p = points[idx];
    if (!marker) {
      marker = L.circleMarker([p.lat, p.lng], { radius:6 }).addTo(map);
    } else {
      marker.setLatLng([p.lat, p.lng]);
    }
    trailPolyline.setLatLngs(points.slice(0, idx+1).map(pt => [pt.lat, pt.lng]));
    map.panTo([p.lat, p.lng], { animate: false });

    const distKm = (cumulativeDistance[idx]/1000).toFixed(2);
    const mode = document.querySelector('input[name="chartMode"]:checked').value;
    const posDs = elevationChart.data.datasets.find(d => d.label === 'Position');
    posDs.yAxisID = mode === 'speed' ? 'ySpeed' : 'yElevation';
    posDs.data[0] = { x: parseFloat(distKm), y: mode === 'speed' ? speedData[idx] : p.ele };
    elevationChart.update('none');

    slider.value = idx;
    document.getElementById('telemetry-elevation').textContent = `${p.ele.toFixed(0)} m`;
    document.getElementById('telemetry-distance').textContent  = `${distKm} km`;
    document.getElementById('telemetry-speed').textContent     = `${speedData[idx].toFixed(1)} km/h`;
  }
  window.updatePlayback = updatePlayback;

  function setupChart() {...}  // existing chart setup code

  // GPX load & parsing
  uploadInput.addEventListener('change', e => {...});  

  // Play/Pause
  playBtn.addEventListener('click', () => {...});

  // Slider scrub
  slider.addEventListener('input', () => {...});

  // Download summary
  summaryBtn.addEventListener('click', () => {...});

  // Save ride
  document.getElementById('save-ride-btn').addEventListener('click', async () => {...});
});
