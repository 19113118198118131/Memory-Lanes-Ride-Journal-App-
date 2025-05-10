// script.js
import supabase from './supabaseClient.js';

document.addEventListener('DOMContentLoaded', async () => {
  // 1️⃣ — Globals & UI refs — must come first
  let points = [];
  let marker = null;
  let trailPolyline = null;
  let elevationChart = null;
  let cumulativeDistance = [];
  let speedData = [];
  let breakPoints = [];
  let accelData = [];
  let selectedSpeedBins = new Set();
  let speedHighlightLayer = null;
  window.playInterval = null;
  window.fracIndex = 0;

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

  // Disable playback controls until a ride is loaded
  [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = true);

  // 2️⃣ — Initialize map
  const map = L.map('leaflet-map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

  // 3️⃣ — Define playback updater
  window.updatePlayback = idx => {
    const p = points[idx];
    if (!marker) {
      marker = L.circleMarker([p.lat, p.lng], { radius: 6, color: '#007bff', fillColor: '#007bff', fillOpacity: 0.9 }).addTo(map);
    } else {
      marker.setLatLng([p.lat, p.lng]);
    }
    trailPolyline.setLatLngs(points.slice(0, idx + 1).map(pt => [pt.lat, pt.lng]));
    map.panTo([p.lat, p.lng], { animate: false });

    const distKm = (cumulativeDistance[idx] / 1000).toFixed(2);
    const mode = document.querySelector('input[name="chartMode"]:checked')?.value || 'elevation';

    // Pause playback when updating from chart click
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      playBtn.textContent = '▶️ Play';
    }

    // Update elevation/speed chart cursor
    const posDs = elevationChart.data.datasets.find(d => d.label === 'Position');
    posDs.yAxisID = mode === 'speed' ? 'ySpeed' : 'yElevation';
    posDs.data[0] = { x: parseFloat(distKm), y: mode === 'speed' ? speedData[idx] : p.ele };
    elevationChart.update('none');

    // Update accel chart cursor
    const existingAccelChart = Chart.getChart(document.getElementById('accelChart'));
    if (existingAccelChart) {
      const accelCursor = existingAccelChart.data.datasets.find(d => d.label === 'Point in Ride');
      if (accelCursor) {
        accelCursor.data[0] = { x: parseFloat(distKm), y: accelData[idx] };
        existingAccelChart.update('none');
      }
    }

    slider.value = idx;
    document.getElementById('telemetry-elevation').textContent = `${p.ele.toFixed(0)} m`;
    document.getElementById('telemetry-distance').textContent = `${distKm} km`;
    document.getElementById('telemetry-speed').textContent = `${speedData[idx].toFixed(1)} km/h`;
  };

  // 4️⃣ — Wire playback controls
  playBtn.addEventListener('click', () => {
    if (!points.length) return;
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      playBtn.textContent = '▶️ Play';
      return;
    }
    window.fracIndex = Number(slider.value);
    playBtn.textContent = '⏸ Pause';
    const mult = parseFloat(speedSel.value) || 1;
    window.playInterval = setInterval(() => {
      window.fracIndex += mult;
      const idx = Math.floor(window.fracIndex);
      if (idx >= points.length) {
        clearInterval(window.playInterval);
        window.playInterval = null;
        playBtn.textContent = '🔁 Replay';
        return;
      }
      window.updatePlayback(idx);
    }, FRAME_DELAY_MS);
  });
  slider.addEventListener('input', () => {
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      playBtn.textContent = '▶️ Play';
    }
    window.updatePlayback(Number(slider.value));
  });

  // 5️⃣ — Speed filter setup (unchanged)
  // ...

  // 8️⃣ — GPX parser & renderer
  async function parseAndRenderGPX(gpxText) {
    // existing parsing code ...
    // after parsing and computing arrays:
    trailPolyline = L.polyline(points.map(p => [p.lat, p.lng]), { color: '#007bff', weight: 3, opacity: 0.7 }).addTo(map).bringToBack();

    setupChart();
    renderSpeedFilter();
    renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);

    [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = false);
    slider.min = 0; slider.max = points.length - 1; slider.value = 0;
    playBtn.textContent = '▶️ Play';
  }

  // 1️⃣3️⃣ — Chart helpers
  function renderAccelChart(accelData, dist, speed, selectedBins, bins) {
    const ctx = document.getElementById('accelChart')?.getContext('2d');
    if (!ctx) return;
    // destroy any existing Chart instance on this canvas
    const old = Chart.getChart(ctx.canvas);
    if (old) old.destroy();

    const accel = dist.map((x, i) => { const y = accelData[i]; return Number.isFinite(y) ? { x: x / 1000, y } : null; }).filter(Boolean);
    const highlights = dist.map((x, i) => { const y = speed[i]; const inBin = selectedBins.some(b => y >= bins[b].min && y < bins[b].max); return inBin && Number.isFinite(y) ? { x: x / 1000, y, idx: i } : null; }).filter(Boolean);
    const values = accel.map(p => p.y);
    const minY = Math.min(...values), maxY = Math.max(...values), buf = (maxY - minY) * 0.1 || 1;

    const datasets = [
      { label: 'Point in Ride', data: [{ x: 0, y: 0 }], type: 'scatter', pointRadius: 5, showLine: false, yAxisID: 'y' },
      { label: 'Acceleration', data: accel, borderWidth: 2, pointRadius: 0, fill: false, yAxisID: 'y' },
      { label: 'Highlighted Speeds', data: highlights, type: 'scatter', pointRadius: 4, showLine: false, yAxisID: 'ySpeed' }
    ];

    new Chart(ctx, {
      type: 'line',
      data: { datasets },
      options: {
        responsive: true,
        animation: false,
        interaction: { mode: 'nearest', intersect: false },
        onClick(evt) {
          const el = this.getElementsAtEventForMode(evt, 'nearest', { intersect: false }, true);
          if (!el.length) return;
          const pt = this.data.datasets[el[0].datasetIndex].data[el[0].index];
          if (pt?.idx != null) window.updatePlayback(pt.idx);
        },
        scales: {
          x: { /* ... */ },
          y: { min: minY - buf, max: maxY + buf },
          ySpeed: { /* ... */ }
        }
      }
    });
  }

  function setupChart() {
    const ctx = document.getElementById('elevationChart').getContext('2d');
    const old = Chart.getChart(ctx.canvas);
    if (old) old.destroy();
    elevationChart = new Chart(ctx, {
      type: 'line',
      data: { datasets: [ /* ... */ ] },
      options: {
        responsive: true,
        animation: false,
        interaction: { mode: 'nearest', intersect: false },
        onClick(evt) {
          const el = this.getElementsAtEventForMode(evt, 'nearest', { intersect: false }, true);
          if (!el.length) return;
          const pt = this.data.datasets[el[0].datasetIndex].data[el[0].index];
          if (pt?.idx != null) window.updatePlayback(pt.idx);
        },
        scales: { /* ... */ }
      }
    });
  }
});
