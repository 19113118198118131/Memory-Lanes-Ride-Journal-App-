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
  const { data: { user } } = await supabase.auth.getUser();
  
  if (!user) {
    document.getElementById('save-ride-form').style.display = 'none';
    document.getElementById('auth-section').style.display = 'block';
  } else {
    document.getElementById('save-ride-form').style.display = 'block';
    document.getElementById('auth-section').style.display = 'none';
  }


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

  saveBtn.addEventListener('click', async () => {
  const title = document.getElementById('ride-title').value.trim();
  const statusEl = document.getElementById('save-status');
  if (!title) {
    statusEl.textContent = '❗ Please enter a ride title.';
    return;
  }

  const { data: { user }, error: userErr } = await supabase.auth.getUser();
  if (userErr || !user) {
    statusEl.textContent = '❌ You must be logged in to save a ride.';
    return;
  }

  const distance_km = parseFloat(distanceEl.textContent);
  const duration_min = parseFloat(rideTimeEl.textContent.split('h')[0]) * 60 +
                       parseFloat(rideTimeEl.textContent.split('h')[1]) || 0;
  const elevation_m = parseFloat(elevationEl.textContent);

  const { error: insertErr } = await supabase.from('ride_logs').insert({
    title,
    user_id: user.id,
    distance_km,
    duration_min,
    elevation_m
  });

  statusEl.textContent = insertErr
    ? `❌ Save failed: ${insertErr.message}`
    : '✅ Ride saved!';
});


  // 🔁 Playback Control
  playBtn.addEventListener('click', () => {
    if (!points.length) return;
    if (playInterval) {
      clearInterval(playInterval);
      playInterval = null;
      playBtn.textContent = '▶️ Play';
      return;
    }
    fracIndex = Number(slider.value);
    playBtn.textContent = '⏸ Pause';
    const mult = parseFloat(speedSel.value) || 1;
    playInterval = setInterval(() => {
      fracIndex += mult;
      const idx = Math.floor(fracIndex);
      if (idx >= points.length) {
        clearInterval(playInterval);
        playInterval = null;
        playBtn.textContent = '🔁 Replay';
        return;
      }
      updatePlayback(idx);
    }, FRAME_DELAY_MS);
  });

  slider.addEventListener('input', () => {
    if (playInterval) {
      clearInterval(playInterval);
      playInterval = null;
      playBtn.textContent = '▶️ Play';
    }
    updatePlayback(Number(slider.value));
  });


  // 🆕 GPX File Upload and Ride Analytics Loader
  uploadInput.addEventListener('change', e => {
    const file = e.target.files[0];
    if (!file) return;
    saveForm.style.display = 'block';

    if (playInterval) clearInterval(playInterval);
    if (marker) map.removeLayer(marker);
    if (trailPolyline) map.removeLayer(trailPolyline);
    points = []; breakPoints = []; cumulativeDistance = []; speedData = []; accelData = [];

    const reader = new FileReader();
    reader.onload = ev => {
      const xml = new DOMParser().parseFromString(ev.target.result, 'application/xml');
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
        const moved = lastLL.distanceTo(L.latLng(pt.lat, pt.lng));
        if (dt >= SAMPLE) {
          if (dt > 180 && moved < 20) {
            breakPoints.push(points.length);
          } else {
            points.push(pt);
            lastTime = pt.time;
            lastLL = L.latLng(pt.lat, pt.lng);
          }
        }
      }
      if (points.at(-1).time !== trkpts.at(-1).time) {
        points.push(trkpts.at(-1));
      }

      cumulativeDistance = [0];
      speedData = [0];
      accelData = [0];
      for (let i = 1; i < points.length; i++) {
        const a = L.latLng(points[i - 1].lat, points[i - 1].lng);
        const b = L.latLng(points[i].lat, points[i].lng);
        const d = a.distanceTo(b);
        const t = (points[i].time - points[i - 1].time) / 1000;
        const v = t > 0 ? (d / t) * 3.6 : 0;
        const dv = v - speedData[i - 1];
        cumulativeDistance[i] = cumulativeDistance[i - 1] + d;
        speedData[i] = v;
        accelData[i] = t > 0 ? (dv / t) : 0;
      }

      const totalMs = points.at(-1).time - points[0].time;
      const totMin = Math.floor(totalMs / 60000);
      const rideSec = points.reduce((sum, _, i) => i > 0 && !breakPoints.includes(i)
        ? sum + ((points[i].time - points[i - 1].time) / 1000)
        : sum, 0);
      const rideMin = Math.floor(rideSec / 60);

      durationEl.textContent = `${Math.floor(totMin / 60)}h ${totMin % 60}m`;
      rideTimeEl.textContent = `${Math.floor(rideMin / 60)}h ${rideMin % 60}m`;
      distanceEl.textContent = `${(cumulativeDistance.at(-1) / 1000).toFixed(2)} km`;
      elevationEl.textContent = `${points.reduce((sum, p, i) =>
        i > 0 && p.ele > points[i - 1].ele ? sum + (p.ele - points[i - 1].ele) : sum
      , 0).toFixed(0)} m`;

      trailPolyline = L.polyline(points.map(p => [p.lat, p.lng]), {
        color: '#007bff', weight: 3, opacity: 0.7
      }).addTo(map).bringToBack();
      map.fitBounds(trailPolyline.getBounds(), { padding: [30, 30], animate: false });

      setupChart();
      renderSpeedFilter();
      renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
      [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = false);
      slider.min = 0; slider.max = points.length - 1; slider.value = 0;
      playBtn.textContent = '▶️ Play';
      if (window.Analytics) Analytics.initAnalytics(points, speedData, cumulativeDistance);
    };
    reader.readAsText(file);
  });

function renderAccelChart(accelData, dist, speed, selectedBins, bins) {
  const ctx = document.getElementById('accelChart')?.getContext('2d');
  if (!ctx) return;
  if (window.accelChart && typeof window.accelChart.destroy === 'function') {
    window.accelChart.destroy();
  }

  const accel = dist.map((x, i) => {
    const y = accelData[i];
    return Number.isFinite(y) ? { x: x / 1000, y } : null;
  }).filter(Boolean);

  const highlightPoints = dist.map((x, i) => {
    const y = speed[i];
    const inBin = selectedBins.some(binIdx => y >= bins[binIdx].min && y < bins[binIdx].max);
    return inBin && Number.isFinite(y) ? { x: x / 1000, y } : null;
  }).filter(Boolean);

  // Dynamically determine accel Y-axis range with a small buffer
  const accelValues = accel.map(p => p.y);
  const accelMin = Math.min(...accelValues);
  const accelMax = Math.max(...accelValues);
  const accelBuffer = (accelMax - accelMin) * 0.1 || 1; // avoid 0 buffer

  const datasets = [
    {
      label: 'Point in Ride',
      data: [{ x: 0, y: 0 }],
      type: 'scatter',
      pointRadius: 5,
      pointBackgroundColor: '#ffffff',
      borderColor: '#ffffff',
      showLine: false,
      yAxisID: 'y'
    },
    {
      label: 'Acceleration',
      data: accel,
      borderColor: '#0168D9',
      borderWidth: 2,
      pointRadius: 0,
      fill: false,
      yAxisID: 'y'
    },
    {
      label: 'Highlighted Speeds',
      data: highlightPoints,
      type: 'scatter',
      pointRadius: 4,
      pointBackgroundColor: '#8338EC',
      borderColor: '#8338EC',
      borderWidth: 1,
      showLine: false,
      yAxisID: 'ySpeed'
    }
  ];

  window.accelChart = new Chart(ctx, {
    type: 'line',
    data: { datasets },
    options: {
      responsive: true,
      animation: false,
      interaction: { mode: 'nearest', intersect: false },
      scales: {
        x: {
          type: 'linear',
          title: { display: true, text: 'Distance (km)' },
          ticks: { callback: v => v.toFixed(2) },
          grid: { color: '#223' }
        },
        y: {
          title: { display: true, text: 'Acceleration (m/s²)' },
          position: 'left',
          min: accelMin - accelBuffer,
          max: accelMax + accelBuffer,
          grid: { color: '#334' }
        },
        ySpeed: {
          title: { display: true, text: 'Speed (km/h)' },
          position: 'right',
          grid: { drawOnChartArea: false }
        }
      },
      plugins: {
        legend: { display: true },
        tooltip: {
          callbacks: {
            label: ctx => `${ctx.dataset.label}: ${ctx.raw.y.toFixed(2)}`
          }
        }
      }
    }
  });
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

    // Update acceleration cursor as well
    if (window.accelChart) {
      const accelCursor = window.accelChart.data.datasets.find(d => d.label === 'Point in Ride');
      if (accelCursor) {
        accelCursor.data[0] = { x: parseFloat(distKm), y: accelData[idx] };
        window.accelChart.update('none');
      }
    }

    slider.value = idx;
    document.getElementById('telemetry-elevation').textContent = `${p.ele.toFixed(0)} m`;
    document.getElementById('telemetry-distance').textContent = `${distKm} km`;
    document.getElementById('telemetry-speed').textContent = `${speedData[idx].toFixed(1)} km/h`;

// 🔵 Update dynamic dot on Acceleration Chart
const posAccelDs = window.accelChart?.data?.datasets?.find(d => d.label === 'Position');
if (posAccelDs) {
  posAccelDs.yAxisID = mode === 'speed' ? 'ySpeed' : 'y';
  posAccelDs.data[0] = {
    x: parseFloat(distKm),
    y: mode === 'speed' ? speedData[idx] : accelData[idx]
  };
  window.accelChart.update('none');
}


    
  };



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
    if (selectedSpeedBins.size === 0) {
      renderAccelChart(accelData, cumulativeDistance, speedData, [], speedBins);
      return;
    }
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
    speedHighlightLayer = L.layerGroup(segments.map(seg => L.polyline(seg, { color: '#8338ec', weight: 5, opacity: 0.8 }))).addTo(map);
    renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
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
