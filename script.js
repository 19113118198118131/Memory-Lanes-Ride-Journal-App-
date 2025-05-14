import supabase from './supabaseClient.js';

document.addEventListener('DOMContentLoaded', async () => {
  // ── grab your ride-driven buttons/sections up front ──
  const slider      = document.getElementById('replay-slider');
  const playBtn     = document.getElementById('play-replay');
  const summaryBtn  = document.getElementById('download-summary');
  const videoBtn    = document.getElementById('export-video');
  const speedSel    = document.getElementById('playback-speed');
  const distanceEl  = document.getElementById('distance');
  const durationEl  = document.getElementById('duration');
  const rideTimeEl  = document.getElementById('ride-time');
  const elevationEl = document.getElementById('elevation');
  const uploadInput = document.getElementById('gpx-upload');
  const saveForm    = document.getElementById('save-ride-form');
  const saveBtn     = document.getElementById('save-ride-btn');
  const authSection = document.getElementById('auth-section');
  const rideTitleDisplay  = document.getElementById('ride-title-display');
  const backBtn           = document.getElementById('back-dashboard');
  const uploadAnotherBtn  = document.getElementById('upload-another');
  const uploadSection     = document.getElementById('upload-section');
  const rideActions       = document.getElementById('ride-actions');

  // 👇 Helpers: toggle our “has-data” CSS class
  function resetToUploadView() {
    document.querySelectorAll('.has-data').forEach(el => el.classList.add('has-data'));
    saveForm.style.display    = 'none';
    authSection.style.display = 'none';
  }
  function showRideUI() {
    document.querySelectorAll('.has-data').forEach(el => el.classList.remove('has-data'));
    // we'll reveal saveForm/authSection later after parsing
  }

  // ❗ Start locked in “just upload” mode
  resetToUploadView();

  // ── Now continue initializing your map, GPX parser, charts, etc. ──

  console.log('script.js loaded');
  window.updatePlayback = null;

  // Initialize map using correct ID
  const map = L.map('leaflet-map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

    // Declare all globals for ride rendering and control
  let points = [], marker = null, trailPolyline = null, elevationChart = null;
  let cumulativeDistance = [], speedData = [], breakPoints = [], accelData = [];
  window.playInterval = null;
      window.jumpToPlaybackIndex = function(idx) {
      if (window.playInterval) {
        clearInterval(window.playInterval);
        window.playInterval = null;
        document.getElementById('play-replay').textContent = '▶️ Play';
      }
      document.getElementById('replay-slider').value = idx;
      window.fracIndex = idx;
      updatePlayback(idx);
    }
  window.fracIndex = 0;
  let speedHighlightLayer = null;
  let selectedSpeedBins = new Set();

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
  
  // ————————————————————————————————
// 0️⃣ Reusable GPX parser + renderer
// ————————————————————————————————
async function parseAndRenderGPX(gpxText) {
  // Parse XML → trackpoints
  const xml = new DOMParser().parseFromString(gpxText, 'application/xml');
  const trkpts = Array.from(xml.getElementsByTagName('trkpt')).map(tp => ({
    lat: +tp.getAttribute('lat'),
    lng: +tp.getAttribute('lon'),
    ele: +tp.getElementsByTagName('ele')[0]?.textContent || 0,
    time: new Date(tp.getElementsByTagName('time')[0]?.textContent)
  })).filter(p => p.lat && p.lng && p.time instanceof Date);

  if (!trkpts.length) return alert('No valid trackpoints found');

  // ↓ Build points[], detect breaks, sample every 5s ↓
  const SAMPLE = 5;
  points = [trkpts[0]];
  breakPoints = [];
  let lastTime = trkpts[0].time;
  let lastLL   = L.latLng(trkpts[0].lat, trkpts[0].lng);

  for (let i = 1; i < trkpts.length; i++) {
    const pt    = trkpts[i];
    const dt    = (pt.time - lastTime) / 1000;
    const moved = lastLL.distanceTo(L.latLng(pt.lat, pt.lng));
    if (dt >= SAMPLE) {
      if (dt > 180 && moved < 20) {
        breakPoints.push(points.length);
      } else {
        points.push(pt);
        lastTime = pt.time;
        lastLL   = L.latLng(pt.lat, pt.lng);
      }
    }
  }
  if (points.at(-1).time !== trkpts.at(-1).time) {
    points.push(trkpts.at(-1));
  }

 // ↓ Compute cumulativeDistance, speedData, accelData ↓
  cumulativeDistance = [0];
  speedData          = [0];
  accelData          = [0];
  for (let i = 1; i < points.length; i++) {
    const a = L.latLng(points[i-1].lat, points[i-1].lng);
    const b = L.latLng(points[i].lat,   points[i].lng);
    const d = a.distanceTo(b); // meters
    const t = (points[i].time - points[i-1].time) / 1000; // seconds
    const v = t > 0 ? d / t : 0; // m/s
  
    cumulativeDistance[i] = cumulativeDistance[i-1] + d;
    speedData[i]          = v * 3.6; // km/h for display only
    accelData[i]          = t > 0 ? (v - (speedData[i-1] / 3.6)) / t : 0; // m/s²
  }


  // ↓ Update summary UI ↓
  const totalMs = points.at(-1).time - points[0].time;
  const totMin  = Math.floor(totalMs / 60000);
  distanceEl.textContent = `${(cumulativeDistance.at(-1) / 1000).toFixed(2)} km`;
  durationEl.textContent = `${Math.floor(totMin / 60)}h ${totMin % 60}m`;
  const rideSec = points.reduce((sum, _, i) =>
    i > 0 && !breakPoints.includes(i)
      ? sum + ((points[i].time - points[i-1].time) / 1000)
      : sum, 0);
  const rideMin = Math.floor(rideSec / 60);
  rideTimeEl.textContent   = `${Math.floor(rideMin / 60)}h ${rideMin % 60}m`;
  elevationEl.textContent  = `${points.reduce((sum, p, i) =>
    i>0 && p.ele>points[i-1].ele ? sum + (p.ele - points[i-1].ele) : sum, 0).toFixed(0)} m`;
  
  // ↓ Draw map trail and fit bounds ↓
  if (trailPolyline) map.removeLayer(trailPolyline);
  trailPolyline = L.polyline(points.map(p => [p.lat, p.lng]), {
    color: '#007bff', weight: 3, opacity: 0.7
  }).addTo(map).bringToBack();
  map.fitBounds(trailPolyline.getBounds(), { padding: [30,30], animate: false });

  // ↓ Build charts & enable controls ↓
  setupChart();
  renderSpeedFilter();
  renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
  [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = false);
  slider.min = 0;
  slider.max = points.length - 1;
  slider.value = 0;
  playBtn.textContent = '▶️ Play';

  if (window.Analytics) {
    Analytics.initAnalytics(points, speedData, cumulativeDistance);
  }

  // ── Reveal everything with data now ──
  showRideUI();

  // 🗺️ Redraw map once visible
  setTimeout(() => map.invalidateSize(), 0);

  // ── Finally, show “Save this ride” OR login/signup ──
  const { data: { user } } = await supabase.auth.getUser();
  if (user) {
    saveForm.style.display    = '';
  } else {
    authSection.style.display = '';
  }




  setTimeout(() => requestAnimationFrame(enableAllControls), 100);
 

// ————————————————————————————————
// 1️⃣ Wire up file‐upload to use the parser
// ————————————————————————————————
uploadInput.addEventListener('change', async e => {
  const file = e.target.files[0];
  if (!file) return;
  // 1) parse & render everything
  const text = await new Promise(r => {
    const rdr = new FileReader();
    rdr.onload = ev => r(ev.target.result);
    rdr.readAsText(file);
  });
  await parseAndRenderGPX(text);

  // 2) reveal map, charts, summary, export/download buttons
  showRideUI();

  // 3) finally, show save or login form
  const { data: { user } } = await supabase.auth.getUser();
  if (user) {
    document.getElementById('save-ride-form').style.display = '';
  } else {
    document.getElementById('auth-section').style.display = '';
  }
});

  
// Grab any ?ride=<id> query parameter
const params = new URLSearchParams(window.location.search);

// 🚩 If returning via “New Ride” button, reset to picker
if (params.get('home') === '1') {
  resetToUploadView();
}

// 🚩 If deep‐linking to an existing ride...
if (params.has('ride')) {
  const rideId = params.get('ride');
  // your existing fetch-and-render logic...
  await fetchAndRenderRide(rideId);
  // then reveal UI & auth/save
  showRideUI();
  const { data: { user } } = await supabase.auth.getUser();
  if (user) {
    document.getElementById('save-ride-form').style.display = '';
  } else {
    document.getElementById('auth-section').style.display = '';
  }
}

  
// If not viewing a ride, hide the viewer buttons
if (!params.has('ride')) {
  rideActions.style.display = 'none';
}

// If viewing a specific ride, handle it
if (params.has('ride')) {
  const rideId = params.get('ride');


  // 1️⃣ Hide the upload form
  document.getElementById('upload-section').style.display = 'none'
   
  
  // 2️⃣ Fetch the stored file path
  const { data: ride, error: rideErr } = await supabase
    .from('ride_logs')
    .select('gpx_path, title')
    .eq('id', rideId)
    .single();
  
  if (rideErr) {
    return alert('Failed to load ride metadata: ' + rideErr.message);
  }
  hideSaveForm();  
  
  rideTitleDisplay.textContent = ride?.title
    ? `📍 Viewing: “${ride.title}”`
    : `📍 Viewing Saved Ride`;
  
  document.getElementById('ride-controls').style.display = 'block';
  rideActions.style.display = 'flex';
  


  // 3️⃣ Build a public URL for that GPX file
  const { data: urlData, error: urlErr } = supabase
    .storage
    .from('gpx-files')
    .getPublicUrl(ride.gpx_path)
  if (urlErr) {
    return alert('Failed to get GPX URL: ' + urlErr.message)
  }

  // 4️⃣ Fetch and render exactly like an upload
  console.log("Fetching GPX file from:", urlData.publicUrl);
  const resp = await fetch(urlData.publicUrl)
  const gpxText = await resp.text()
  console.log("Fetched GPX content length:", gpxText.length);
  await parseAndRenderGPX(gpxText);
  console.log("Finished rendering GPX");
}
  
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
  const params = new URLSearchParams(window.location.search);
  const viewingRide = params.has('ride');
  
  // Show save form only if not viewing a ride
  document.getElementById('save-ride-form').style.display = viewingRide ? 'none' : 'block';
  document.getElementById('auth-section').style.display = 'none';
}


  // ✅ Force re-enable playback controls after auth and DOM visibility
  setTimeout(() => requestAnimationFrame(enableAllControls), 100);



  // --- Login / Signup handlers ---

  document.getElementById('login-btn').addEventListener('click', async () => {
  const email = document.getElementById('auth-email').value;
  const pass = document.getElementById('auth-password').value;
  const statusEl = document.getElementById('auth-status');

  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password: pass
  });

  console.log('login result', data, error);
  console.log('statusEl exists:', !!statusEl);
  console.log('auth-status content BEFORE:', statusEl?.innerHTML);

  if (error) {
    statusEl.textContent = `❌ Login failed: ${error.message}`;
    return;
  }

  // Clear any old errors (like "must be logged in")
  statusEl.textContent = '';  

  // Show success message
  statusEl.innerHTML = `
  ✅ Login successful!
  <button id="go-dashboard" style="
    margin-left: 1rem;
    padding: 0.4rem 1rem;
    font-weight: bold;
    font-size: 0.9rem;
    background: transparent;
    color: #64ffda;
    border: 1px solid #64ffda;
    border-radius: 5px;
    cursor: pointer;
    transition: background 0.2s;
  ">Go to Dashboard</button>
`;
  document.getElementById('save-status').textContent = '';
  
  // Show styled success
  statusEl.style.display = 'block';
  statusEl.style.color = '#64ffda';
  statusEl.style.padding = '0.75rem';
  statusEl.style.fontWeight = 'bold';
  statusEl.style.border = '1px solid #64ffda';
  statusEl.style.background = '#112240';
  statusEl.style.borderRadius = '5px';
  statusEl.style.marginTop = '1rem';
  
  // Delay hiding auth section so success message can render first
  setTimeout(() => {
    document.getElementById('auth-section').style.display = 'none';
  }, 50);
  
  // Show save form
  document.getElementById('save-ride-form').style.display = 'block';


setTimeout(() => {
  const dashBtn = document.getElementById('go-dashboard');
  const navContainer = document.getElementById('ride-card-nav');
  if (dashBtn && navContainer) {
    navContainer.appendChild(dashBtn); // 💡 Move button visually
    dashBtn.addEventListener('click', () => {
      window.location.href = 'dashboard.html';
    });
  }
}, 0);

});



  document.getElementById('signup-btn').addEventListener('click', async () => {
    const email = document.getElementById('auth-email').value;
    const pass = document.getElementById('auth-password').value;
    const { data, error } = await supabase.auth.signUp({ email, password: pass });
    document.getElementById('auth-status').textContent = error
      ? 'Signup failed: ' + error.message
      : 'Signup OK! Check your email, then login above.';
  });

  



  [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = true);

  saveBtn.addEventListener('click', async () => {
  const title = document.getElementById('ride-title').value.trim();
  const statusEl = document.getElementById('save-status');
  if (!title) {
    statusEl.textContent = '❗ Please enter a ride title.';
    return;
  }

  const sessionResult = await supabase.auth.getSession();
  const user = sessionResult.data?.session?.user;

  if (!user) {
    statusEl.textContent = '❌ You must be logged in to save a ride.';
    return;
  }

  // —————————————
  // 1️⃣ UPLOAD THE RAW GPX TO STORAGE
  // —————————————
  const file = uploadInput.files[0];
  if (!file) {
    statusEl.textContent = '❗ No GPX file selected.';
    return;
  }
  // build a unique path: userId/timestamp.gpx
  const ext      = file.name.split('.').pop();
  const stamp    = Date.now();
  const filePath = `${user.id}/${stamp}.${ext}`;

  const { data: uploadData, error: uploadErr } = await supabase
    .storage
    .from('gpx-files')
    .upload(filePath, file);

  if (uploadErr) {
    statusEl.textContent = `❌ GPX upload failed: ${uploadErr.message}`;
    return;
  }

  // —————————————
  // 2️⃣ COMPUTE YOUR RIDE METRICS
  // —————————————
  const distance_km  = parseFloat(distanceEl.textContent);
  const duration_min = parseFloat(rideTimeEl.textContent.split('h')[0]) * 60 +
                       (parseFloat(rideTimeEl.textContent.split('h')[1]) || 0);
  const elevation_m  = parseFloat(elevationEl.textContent);
  
  // —————————————
  // 3️⃣ INSERT LOG WITH gpx_path
  // —————————————
  const ride_date = points[0].time.toISOString(); // preserve timezone
    
  const { data: insertData, error: insertErr } = await supabase
    .from('ride_logs')
    .insert({
      title,
      user_id:     user.id,
      distance_km,
      duration_min,
      elevation_m,
      ride_date,
      gpx_path:    uploadData.path    // ← store the bucket path
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
    window.fracIndex = Number(slider.value);
    playBtn.textContent = '⏸ Pause';
    const mult = parseFloat(speedSel.value) || 1;
    playInterval = setInterval(() => {
      window.fracIndex += mult;
    const idx = Math.floor(window.fracIndex);
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

let highlightPoints = dist.map((x, i) => {
  const y = speed[i];
  return Number.isFinite(y) ? { x: x / 1000, y, idx: i } : null;
}).filter(Boolean);

if (selectedBins.length > 0) {
  highlightPoints = highlightPoints.filter(p =>
    selectedBins.some(binIdx => p.y >= bins[binIdx].min && p.y < bins[binIdx].max)
  );
}
  

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
      onClick: function(evt) {
        // ⏸ Stop playback if playing
        if (window.playInterval) {
          clearInterval(window.playInterval);
          window.playInterval = null;
          playBtn.textContent = '▶️ Play';
        }
    
        const elements = this.getElementsAtEventForMode(evt,'nearest',{ intersect:false },true);
        if (!elements.length) return;
        const dataPoint = this.data.datasets[elements[0].datasetIndex].data[elements[0].index];
        if (dataPoint && typeof dataPoint.idx === 'number') {
          window.jumpToPlaybackIndex(dataPoint.idx);
        }
      },


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
    const posDs = elevationChart.data.datasets.find(d => d.label === 'Point in Ride');
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
const posAccelDs = window.accelChart?.data?.datasets?.find(d => d.label === 'Point in Ride');
if (posAccelDs) {
  posAccelDs.yAxisID = mode === 'speed' ? 'ySpeed' : 'y';
  posAccelDs.data[0] = {
    x: parseFloat(distKm),
    y: mode === 'speed' ? speedData[idx] : accelData[idx]
  };
  window.accelChart.update('none');
}


    
  };






  function setupChart() {
    const ctx = document.getElementById('elevationChart').getContext('2d');
    if (elevationChart) elevationChart.destroy();
    elevationChart = new Chart(ctx, {
      type: 'line',
      data: {
        datasets: [
          {
            label: 'Elevation',
            data: points.map((p, i) => ({ x: cumulativeDistance[i]/1000, y: p.ele, idx: i })),
            borderColor: '#64ffda',
            backgroundColor: (() => {
              const g = ctx.createLinearGradient(0,0,0,200);
              g.addColorStop(0, 'rgba(100,255,218,0.4)');
              g.addColorStop(1, 'rgba(100,255,218,0)');
              return g;
            })(),
            borderWidth: 2,
            tension: 0.3,
            pointRadius: 0,
            fill: true,
            yAxisID: 'yElevation'
          },
          {
            label: 'Point in Ride',
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
            data: points.map((p, i) => ({ x: cumulativeDistance[i]/1000, y: speedData[i], idx: i })),
            borderColor: '#ff6384',
            backgroundColor: (() => {
              const g = ctx.createLinearGradient(0, 0, 0, 200);
              g.addColorStop(0, 'rgba(255,99,132,0.4)');
              g.addColorStop(1, 'rgba(255,99,132,0)');
              return g;
            })(),
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
      interaction: { mode: 'nearest', intersect: false },
      onClick: function(evt) {
        // ⏸ Stop playback if playing
        if (window.playInterval) {
          clearInterval(window.playInterval);
          window.playInterval = null;
          playBtn.textContent = '▶️ Play';
        }
    
        const elements = this.getElementsAtEventForMode(evt,'nearest',{ intersect:false },true);
        if (!elements.length) return;
        const dataPoint = this.data.datasets[elements[0].datasetIndex].data[elements[0].index];
        if (dataPoint && typeof dataPoint.idx === 'number') {
          window.jumpToPlaybackIndex(dataPoint.idx);
        }
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
            title: { display: true, text: 'Speed (km/h)' },
            position: 'right',
            min: 0, // always makes sense for speed
            grid: { drawOnChartArea: false },
            ticks: {
              stepSize: 20,
              callback: v => v.toFixed(0)
            }
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

  
function enableAllControls() {
  ['replay-slider', 'play-replay', 'download-summary', 'export-video', 'playback-speed'].forEach(id => {
    const el = document.getElementById(id);
    if (el) {
      el.disabled = false;
      el.removeAttribute('disabled');
      el.classList.remove('disabled');
      el.style.opacity = '1';
      el.style.pointerEvents = 'auto';
    }
  });
}


