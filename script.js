// script.js
import supabase from './supabaseClient.js';

console.log('script.js loaded');
window.updatePlayback = null;

document.addEventListener('DOMContentLoaded', async () => {
  // 1️⃣ Auth check: if not signed in, hide the map and show the login form
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) {
    console.error('Not logged in:', userError);
    // hide everything except the auth UI
    document.getElementById('upload-section').style.display   = 'none';
    document.getElementById('map-section').style.display      = 'none';
    document.getElementById('summary-section').style.display  = 'none';
    document.getElementById('timeline').style.display         = 'none';
    document.getElementById('auth-section').style.display     = '';
    // stop here
    return;
  } else {
    // we *are* signed in, so hide the login form
    document.getElementById('auth-section').style.display     = 'none';
  }

  // 2️⃣ Leaflet map setup (match your <div id="map">)
  const map = L.map('leaflet-map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

  // 3️⃣ GPX loader helper (Omnivore URL‐loader style)
  function loadAndDisplayGPX(url) {
    console.log('Loading GPX from', url);
    const gpxLayer = omnivore.gpx(url)
      .on('ready', e => {
        map.fitBounds(e.target.getBounds());
        // re‐render charts if available
        fetch(url)
          .then(r => r.text())
          .then(text => {
            if (typeof renderChartsFromGPXText === 'function') {
              renderChartsFromGPXText(text);
            }
          })
          .catch(err => console.warn('Chart render failed', err));
      });
    if (window.currentGPX) map.removeLayer(window.currentGPX);
    window.currentGPX = gpxLayer.addTo(map);
  }

  // 4️⃣ Auto-load ride if coming back from dashboard
  const selectedRideId = localStorage.getItem('selectedRideId');
  if (selectedRideId) {
    console.log('Auto-loading ride id', selectedRideId);
    localStorage.removeItem('selectedRideId');
    const { data, error } = await supabase
      .from('ride_logs')
      .select('title, distance_km, duration_min, elevation_m, gpx_url')
      .eq('id', selectedRideId)
      .single();
    if (error) {
      console.error('Failed to load ride metadata:', error);
    } else {
      document.getElementById('ride-title').value = data.title;
      document.getElementById('save-ride-form').style.display = 'block';
      document.getElementById('distance').textContent = `${data.distance_km.toFixed(2)} km`;
      document.getElementById('duration').textContent = `${data.duration_min} min`;
      document.getElementById('elevation').textContent = `${data.elevation_m} m`;
      if (data.gpx_url) loadAndDisplayGPX(data.gpx_url);
    }
  }

  // — Globals & DOM refs —
  let points = [], marker = null, trailPolyline = null;
  let elevationChart = null, cumulativeDistance = [], speedData = [];
  let breakPoints = [], playInterval = null, fracIndex = 0;
  let speedHighlightLayer = null, selectedSpeedBins = new Set(), accelData = [];

  const FRAME_DELAY_MS = 50;
  const uploadInput = document.getElementById('gpx-upload');
  const saveForm    = document.getElementById('save-ride-form');
  const saveBtn     = document.getElementById('save-ride-btn');
  const distanceEl  = document.getElementById('distance');
  const durationEl  = document.getElementById('duration');
  const rideTimeEl  = document.getElementById('ride-time');
  const elevationEl = document.getElementById('elevation');
  const slider      = document.getElementById('replay-slider');
  const playBtn     = document.getElementById('play-replay');
  const summaryBtn  = document.getElementById('download-summary');
  const videoBtn    = document.getElementById('export-video');
  const speedSel    = document.getElementById('playback-speed');

  [uploadInput, slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => {
    if (el) el.disabled = true;
  });

  // — Speed‐filter bins & UI —
  const speedBins = [
    { label: '50–80',  min: 50,  max:  80 },
    { label: '80–100', min: 80,  max: 100 },
    { label: '100–120',min:100,  max: 120 },
    { label: '120–160',min:120,  max: 160 },
    { label: '160–200',min:160,  max: 200 },
    { label: '200+',   min:200,  max: Infinity }
  ];
  function renderSpeedFilter() {
    const container = document.getElementById('speed-bins');
    container.innerHTML = '';
    speedBins.forEach((bin,i) => {
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
    if (!btn) return;
    const isActive = selectedSpeedBins.has(binIndex);
    isActive ? selectedSpeedBins.delete(binIndex) : selectedSpeedBins.add(binIndex);
    btn.classList.toggle('active', !isActive);
    if (speedHighlightLayer) map.removeLayer(speedHighlightLayer);
    if (selectedSpeedBins.size === 0) {
      renderAccelChart(accelData, cumulativeDistance, speedData, [], speedBins);
      return;
    }
    const segments = [];
    for (let i = 1; i < points.length; i++) {
      const s = speedData[i];
      for (let b of selectedSpeedBins) {
        const { min, max } = speedBins[b];
        if (s >= min && s < max) {
          segments.push([[points[i-1].lat,points[i-1].lng],[points[i].lat,points[i].lng]]);
          break;
        }
      }
    }
    speedHighlightLayer = L.layerGroup(segments.map(seg => {
      const pl = L.polyline(seg,{weight:5,opacity:0.8});
      pl.on('add', ()=> pl._path?.classList.add('pulse-line'));
      return pl;
    })).addTo(map);
    renderAccelChart(accelData, cumulativeDistance, speedData, [...selectedSpeedBins], speedBins);
  }

  // — Playback & charts (reuse your existing code) —
  function updatePlayback(idx) { /*…*/ }
  window.updatePlayback = updatePlayback;
  function setupChart()     { /*…*/ }

  // — GPX upload & parsing —
  uploadInput.addEventListener('change', e => {
    const file = e.target.files[0];
    if (!file) return alert('No GPX file selected');
    saveForm.style.display = 'block';
    if (marker) map.removeLayer(marker);
    if (trailPolyline) map.removeLayer(trailPolyline);
    if (playInterval) clearInterval(playInterval);
    points = []; breakPoints = [];

    const reader = new FileReader();
    reader.onload = ev => {
      // … your existing FileReader parsing logic …
    };
    reader.readAsText(file);
  });

  // — Controls: Play/Pause, Slider, Download summary, Save ride —
  playBtn.addEventListener('click', () => { /*…*/ });
  slider.addEventListener('input', () => { /*…*/ });
  summaryBtn.addEventListener('click', () => { /*…*/ });
  saveBtn.addEventListener('click', async () => { /*…*/ });
});
