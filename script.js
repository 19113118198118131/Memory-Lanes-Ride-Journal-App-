// script.js 
import supabase from './supabaseClient.js';

console.log('script.js loaded');
window.updatePlayback = null;

document.addEventListener('DOMContentLoaded', async () => {
  // Redirect clean-up from Supabase
  if (window.location.hash.includes('type=signup')) {
    document.getElementById('auth-status').textContent = '✅ Email confirmed! Please log in now.';
    history.replaceState({}, document.title, window.location.pathname);
  }
  if (window.location.hash.includes('access_token')) {
    history.replaceState({}, document.title, window.location.pathname);
  }

  // Hide forms initially
  document.getElementById('save-ride-form').style.display = 'none';
  document.getElementById('auth-section').style.display = 'none';

  // --- Login / Signup handlers ---
  document.getElementById('login-btn').addEventListener('click', async () => {
    const email = document.getElementById('auth-email').value;
    const pass = document.getElementById('auth-password').value;
    const { data, error } = await supabase.auth.signInWithPassword({ email, password: pass });
    document.getElementById('auth-status').textContent = error
      ? 'Login failed: ' + error.message
      : 'Login successful!';
    if (!error) {
      document.getElementById('auth-section').style.display = 'none';
      document.getElementById('save-ride-form').style.display = 'block';
    }
  });

  document.getElementById('signup-btn').addEventListener('click', async () => {
    const email = document.getElementById('auth-email').value;
    const pass = document.getElementById('auth-password').value;
    const { data, error } = await supabase.auth.signUp({ email, password: pass });
    document.getElementById('auth-status').textContent = error
      ? 'Signup failed: ' + error.message
      : 'Signup OK! Check your email, then login above.';
  });

  // Initialize map using correct ID
  const map = L.map('leaflet-map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

  // Declare all globals for ride rendering and control
  let points = [], marker = null, trailPolyline = null, elevationChart = null;
  let cumulativeDistance = [], speedData = [], breakPoints = [], accelData = [];
  let playInterval = null, fracIndex = 0, speedHighlightLayer = null, selectedSpeedBins = new Set();
  const FRAME_DELAY_MS = 50;

  const slider = document.getElementById('replay-slider');
  const playBtn = document.getElementById('play-replay');
  const summaryBtn = document.getElementById('download-summary');
  const videoBtn = document.getElementById('export-video');
  const speedSel = document.getElementById('playback-speed');
  const distanceEl = document.getElementById('distance');
  const durationEl = document.getElementById('duration');
  const rideTimeEl = document.getElementById('ride-time');
  const elevationEl = document.getElementById('elevation');
  const uploadInput = document.getElementById('gpx-upload');

  const saveForm = document.getElementById('save-ride-form');
  const saveBtn = document.getElementById('save-ride-btn');

  [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = true);

  const speedBins = [
    { label: '50–80', min: 50, max: 80 },
    { label: '80–100', min: 80, max: 100 },
    { label: '100–120', min: 100, max: 120 },
    { label: '120–160', min: 120, max: 160 },
    { label: '160–200', min: 160, max: 200 },
    { label: '200+', min: 200, max: Infinity }
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

  function highlightSpeedBin(i) {
    const btn = document.querySelector(`#speed-bins .speed-bin-btn[data-index="${i}"]`);
    const isActive = selectedSpeedBins.has(i);
    isActive ? selectedSpeedBins.delete(i) : selectedSpeedBins.add(i);
    btn.classList.toggle('active', !isActive);
    if (speedHighlightLayer) map.removeLayer(speedHighlightLayer);
    if (selectedSpeedBins.size === 0) return;
    const segments = [];
    for (let j = 1; j < points.length; j++) {
      const speed = speedData[j];
      for (let b of selectedSpeedBins) {
        if (speed >= speedBins[b].min && speed < speedBins[b].max) {
          segments.push([[points[j-1].lat, points[j-1].lng], [points[j].lat, points[j].lng]]);
          break;
        }
      }
    }
    speedHighlightLayer = L.layerGroup(segments.map(seg => L.polyline(seg, { weight: 5, opacity: 0.8 }))).addTo(map);
  }

  window.updatePlayback = idx => {
    const p = points[idx];
    if (!marker) {
      marker = L.circleMarker([p.lat, p.lng], { radius: 6, color: '#007bff', fillColor: '#007bff', fillOpacity: 0.9 }).addTo(map);
    } else {
      marker.setLatLng([p.lat, p.lng]);
    }
    trailPolyline.setLatLngs(points.slice(0, idx + 1).map(pt => [pt.lat, pt.lng]));
    map.panTo([p.lat, p.lng], { animate: false });

    const distKm = (cumulativeDistance[idx]/1000).toFixed(2);
    const mode = document.querySelector('input[name="chartMode"]:checked')?.value || 'elevation';
    const posDs = elevationChart.data.datasets.find(d => d.label === 'Position');
    posDs.yAxisID = mode === 'speed' ? 'ySpeed' : 'yElevation';
    posDs.data[0] = { x: parseFloat(distKm), y: mode === 'speed' ? speedData[idx] : p.ele };
    elevationChart.update('none');

    slider.value = idx;
    document.getElementById('telemetry-elevation').textContent = `${p.ele.toFixed(0)} m`;
    document.getElementById('telemetry-distance').textContent = `${distKm} km`;
    document.getElementById('telemetry-speed').textContent = `${speedData[idx].toFixed(1)} km/h`;
  }

  function setupChart() {
    const ctx = document.getElementById('elevationChart').getContext('2d');
    if (elevationChart) elevationChart.destroy();
    elevationChart = new Chart(ctx, {
      type: 'line',
      data: {
        datasets: [
          {
            label: 'Elevation',
            data: points.map((p, i) => ({ x: cumulativeDistance[i]/1000, y: p.ele })),
            borderColor: '#64ffda',
            backgroundColor: (() => {
              const g = ctx.createLinearGradient(0,0,0,200);
              g.addColorStop(0, 'rgba(100,255,218,0.5)');
              g.addColorStop(1, 'rgba(10,25,47,0.1)');
              return g;
            })(),
            borderWidth: 2,
            tension: 0.3,
            pointRadius: 0,
            fill: true,
            yAxisID: 'yElevation'
          },
          {
            label: 'Position',
            data: [{ x: 0, y: points[0] ? points[0].ele : 0 }],
            type: 'scatter',
            pointRadius: 5,
            pointBackgroundColor: '#fff',
            showLine: false,
            yAxisID: 'yElevation'
          },
          {
            label: 'Breaks',
            data: breakPoints.map(i => ({ x: cumulativeDistance[i]/1000, y: points[i].ele })),
            type: 'scatter',
            pointRadius: 3,
            pointBackgroundColor: 'rgba(150,150,150,0.6)',
            showLine: false,
            yAxisID: 'yElevation'
          },
          {
            label: 'Speed (km/h)',
            data: points.map((p, i) => ({ x: cumulativeDistance[i]/1000, y: speedData[i] })),
            borderColor: '#ff6384',
            backgroundColor: 'rgba(255,99,132,0.1)',
            borderWidth: 2,
            tension: 0.3,
            pointRadius: 0,
            fill: true,
            yAxisID: 'ySpeed'
          }
        ]
      },
      options: {
        responsive: true,
        animation: false,
        interaction: { mode: 'nearest', intersect: false, axis: 'x' },
        onClick: (evt, elems) => {
          if (!elems.length) return;
          const idx = elems[0].index;
          updatePlayback(idx);
        },
        scales: {
          x: {
            type: 'linear',
            title: { display: true, text: 'Distance (km)' },
            grid: { color: '#223' },
            ticks: { callback: v => v.toFixed(2) }
          },
          yElevation: {
            display: true,
            position: 'left',
            title: { display: true, text: 'Elevation (m)' },
            grid: { color: '#334' }
          },
          ySpeed: {
            display: true,
            position: 'right',
            title: { display: true, text: 'Speed (km/h)' },
            grid: { drawOnChartArea: false }
          }
        },
        plugins: {
          legend: { display: true },
          tooltip: {
            callbacks: { label: ctx => `${ctx.dataset.label}: ${ctx.raw.y.toFixed(1)}` }
          }
        }
      }
    });

    document.querySelectorAll('input[name="chartMode"]').forEach(radio => {
      radio.addEventListener('change', () => {
        const mode = document.querySelector('input[name="chartMode"]:checked').value;
        elevationChart.data.datasets.forEach(ds => {
          if (ds.label === 'Elevation' || ds.label === 'Breaks') ds.hidden = (mode === 'speed');
          else if (ds.label === 'Speed (km/h)') ds.hidden = (mode === 'elevation');
        });
        elevationChart.options.scales.yElevation.display = (mode !== 'speed');
        elevationChart.options.scales.ySpeed.display     = (mode !== 'elevation');
        elevationChart.update();
      });
    });
  }
});
