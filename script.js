// script.js

// 1) Imports & Supabase init (must be at the very top)
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
const SUPABASE_URL     = 'https://vodujxiwkpxaxaqnwkdd.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZvZHVqeGl3a3B4YXhhcW53a2RkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY3NTgwOTQsImV4cCI6MjA2MjMzNDA5NH0.k4NeZ3dgqe1QQeXmkmgThp-X_PwOHPHLAQErg3hrPok';
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.supabase = supabase;

// 2) Globals
console.log('script.js loaded');
window.updatePlayback = null;
let map, marker, trailPolyline;
let points = [], breakPoints = [], cumulativeDistance = [], speedData = [], playInterval = null;

// 3) Preload-from-URL block
;(async () => {
  const params = new URLSearchParams(window.location.search);
  const url = params.get('gpx');
  if (url) {
    try {
      const resp = await fetch(url);
      const text = await resp.text();
      loadGPXFromText(text);
    } catch (error) {
      console.error('Failed to preload GPX:', error);
    }
  }
})();

// 4) Chart & filter functions (from v2)
function setupChart() {
  const ctx = document.getElementById('elevation-chart').getContext('2d');
  if (window.elevationChart) elevationChart.destroy();
  window.elevationChart = new Chart(ctx, {
    type: 'line',
    data: { datasets: [ /* ... existing datasets config ... */ ] },
    options: { responsive: true, animation: false, /* ... existing options ... */ }
  });
  document.querySelectorAll('input[name="chartMode"]').forEach(radio => {
    radio.addEventListener('change', () => {
      const mode = document.querySelector('input[name="chartMode"]:checked').value;
      window.elevationChart.data.datasets.forEach(ds => {
        ds.hidden = (ds.label === 'Elevation' && mode === 'speed')
          || (ds.label === 'Speed (km/h)' && mode === 'elevation');
      });
      window.elevationChart.update();
    });
  });
}

function renderSpeedFilter() {
  // ... existing v2 speed filter rendering code ...
}

// 5) Playback update with restored styling
function updatePlayback(idx) {
  const p = points[idx];
  if (!marker) {
    marker = L.circleMarker([p.lat, p.lng], {
      radius: 6,
      color: '#007bff',
      fillColor: '#007bff',
      fillOpacity: 0.9
    }).addTo(map);
  } else {
    marker.setLatLng([p.lat, p.lng]);
  }
  trailPolyline.setLatLngs(points.slice(0, idx + 1).map(pt => [pt.lat, pt.lng]));
}

// 6) GPX parsing & UI init (restored from v1)
function loadGPXFromText(text) {
  document.getElementById('save-ride-form').style.display = 'block';
  if (playInterval) clearInterval(playInterval);
  if (marker) map.removeLayer(marker);
  if (trailPolyline) map.removeLayer(trailPolyline);
  points = [];
  breakPoints = [];

  const xml = new DOMParser().parseFromString(text, 'application/xml');
  const trkpts = Array.from(xml.getElementsByTagName('trkpt')).map(tp => ({
    lat: +tp.getAttribute('lat'),
    lng: +tp.getAttribute('lon'),
    ele: +tp.getElementsByTagName('ele')[0]?.textContent || 0,
    time: new Date(tp.getElementsByTagName('time')[0]?.textContent)
  })).filter(p => p.lat && p.lng && p.time instanceof Date);
  if (!trkpts.length) return alert('No valid trackpoints found');

  const SAMPLE = 5;
  let lastTime = trkpts[0].time;
  let lastLL = L.latLng(trkpts[0].lat, trkpts[0].lng);
  points.push(trkpts[0]);
  for (let i = 1; i < trkpts.length; i++) {
    const pt = trkpts[i];
    const dt = (pt.time - lastTime) / 1000;
    const dist = lastLL.distanceTo(L.latLng(pt.lat, pt.lng));
    if (dt > SAMPLE && dist > 0) {
      breakPoints.push(points.length);
      points.push(pt);
      lastTime = pt.time;
      lastLL = L.latLng(pt.lat, pt.lng);
    } else {
      points.push(pt);
      lastTime = pt.time;
      lastLL = L.latLng(pt.lat, pt.lng);
    }
  }
  if (points.at(-1).time !== trkpts.at(-1).time) points.push(trkpts.at(-1));

  cumulativeDistance = [0];
  speedData = [0];
  for (let i = 1; i < points.length; i++) {
    const d = L.latLng(points[i - 1].lat, points[i - 1].lng)
      .distanceTo(L.latLng(points[i].lat, points[i].lng));
    const t = (points[i].time - points[i - 1].time) / 1000;
    cumulativeDistance[i] = cumulativeDistance[i - 1] + d;
    speedData[i] = t > 0 ? (d / t) * 3.6 : 0;
  }
  const totalMs = points.at(-1).time - points[0].time;
  const totMin = Math.floor(totalMs / 60000);
  const rideSec = points.reduce((sum, _, i) =>
    i > 0 && !breakPoints.includes(i)
      ? sum + ((points[i].time - points[i - 1].time) / 1000)
      : sum, 0);
  const rideMin = Math.floor(rideSec / 60);

  document.getElementById('duration').textContent = `${Math.floor(totMin/60)}h ${totMin%60}m`;
  document.getElementById('ride-time').textContent = `${Math.floor(rideMin/60)}h ${rideMin%60}m`;
  document.getElementById('distance').textContent = `${(cumulativeDistance.at(-1)/1000).toFixed(2)} km`;
  document.getElementById('elevation').textContent = `${points.reduce((sum, p, i) =>
    i>0 && p.ele>points[i-1].ele ? sum + (p.ele-points[i-1].ele) : sum, 0).toFixed(0)} m`;

  trailPolyline = L.polyline(points.map(p => [p.lat, p.lng]), {
    color: '#007bff', weight: 3, opacity: 0.7
  }).addTo(map).bringToBack();
  map.fitBounds(trailPolyline.getBounds(), { padding: [30, 30], animate: false });

  setupChart();
  [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = false);
  slider.min = 0;
  slider.max = points.length - 1;
  slider.value = 0;
  playBtn.textContent = '▶️ Play';
  renderSpeedFilter();
  if (window.Analytics) Analytics.initAnalytics(points, speedData, cumulativeDistance);
}

// 7) DOMContentLoaded: initialize map, UI event handlers
window.addEventListener('DOMContentLoaded', () => {
  // initialize map
  map = L.map('map').setView([-36.8485, 174.7633], 13);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);

  // UI references
  const uploadInput = document.getElementById('gpx-upload');
  const slider = document.getElementById('slider');
  const playBtn = document.getElementById('play-btn');
  const summaryBtn = document.getElementById('summary-btn');
  const videoBtn = document.getElementById('video-btn');
  const speedSel = document.getElementById('speed-select');
  const durationEl = document.getElementById('duration');
  const rideTimeEl = document.getElementById('ride-time');
  const distanceEl = document.getElementById('distance');
  const elevationEl = document.getElementById('elevation');

  document.getElementById('save-ride-form').style.display = 'none';

  // GPX file input
  uploadInput.addEventListener('change', async e => {
    const file = e.target.files[0];
    if (!file) return;
    const text = await file.text();
    loadGPXFromText(text);
  });

  // Play/Pause (v2 logic)
  playBtn.addEventListener('click', () => {
    if (!points.length) return;
    if (playInterval) {
      clearInterval(playInterval);
      playInterval = null;
      playBtn.textContent = '▶️ Play';
      return;
    }
    if (playBtn.textContent === '🔁 Replay') {
      slider.value = 0;
      updatePlayback(0);
      playBtn.textContent = '▶️ Play';
      return;
    }
    playBtn.textContent = '⏸ Pause';
    playInterval = setInterval(() => {
      const idx = Number(slider.value) + 1;
      if (idx >= points.length) {
        clearInterval(playInterval);
        playInterval = null;
        playBtn.textContent = '🔁 Replay';
      } else {
        slider.value = idx;
        updatePlayback(idx);
      }
    }, 200);
  });

  // Slider scrub
  slider.addEventListener('input', () => {
    if (playInterval) {
      clearInterval(playInterval);
      playInterval = null;
      playBtn.textContent = '▶️ Play';
    }
    updatePlayback(Number(slider.value));
  });

  // Download summary
  summaryBtn.addEventListener('click', () => {
    const txt =
      `Distance: ${distanceEl.textContent}\n` +
      `Total Duration: ${durationEl.textContent}\n` +
      `Ride Time: ${rideTimeEl.textContent}\n` +
      `Elevation Gain: ${elevationEl.textContent}`;
    const blob = new Blob([txt], { type: 'text/plain' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'ride-summary.txt';
    a.click();
  });

  // Save ride (v2 + restored disable/enable)
  const saveBtn = document.getElementById('save-ride-btn');
  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true;
    const user = supabase.auth.user();
    const file = document.getElementById('gpx-upload').files[0];
    if (!file) {
      document.getElementById('save-status').textContent = 'No GPX file to save!';
      saveBtn.disabled = false;
      return;
    }
    const timestamp = Date.now();
    const filename = `${user.id}/${timestamp}-${file.name}`;
    const { error: uploadErr } = await supabase
      .storage
      .from('gpx-files')
      .upload(filename, file, { cacheControl: '3600', upsert: false });
    if (uploadErr) {
      document.getElementById('save-status').textContent = '❌ Upload failed: ' + uploadErr.message;
      saveBtn.disabled = false;
      return;
    }

    const title = document.getElementById('ride-title').value;
    const distance_km = parseFloat(distanceEl.textContent);
    const durationParts = durationEl.textContent.match(/(\d+)h\s*(\d+)m/);
    const duration_min = parseInt(durationParts[1]) * 60 + parseInt(durationParts[2]);
    const elevation_m = parseInt(elevationEl.textContent);
    const { error: insertErr } = await supabase
      .from('ride_logs')
      .insert([{ user_id: user.id, title, distance_km, duration_min, elevation_m, gpx_path: filename, track: points }]);

    document.getElementById('save-status').textContent = insertErr
      ? '❌ Save failed: ' + insertErr.message
      : '✅ Ride saved successfully!';
    saveBtn.disabled = false;
    if (!insertErr) {
      document.getElementById('save-ride-form').style.display = 'none';
      document.getElementById('ride-title').value = '';
    }
  });
});
