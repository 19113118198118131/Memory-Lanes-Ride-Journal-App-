// script.js
import supabase from './supabaseClient.js';

console.log('script.js loaded');
window.updatePlayback = null;

document.addEventListener('DOMContentLoaded', async () => {

    // Hide the “save” form & login form on load
    document.getElementById('save-ride-form').style.display = 'none';
    document.getElementById('auth-section').style.display  = 'none';

    // --- Login / Signup handlers ---
    const authSection = document.getElementById('auth-section');
    const loginBtn    = document.getElementById('login-btn');
    const signupBtn   = document.getElementById('signup-btn');
    const authStatus  = document.getElementById('auth-status');

    loginBtn.addEventListener('click', async () => {
      const email = document.getElementById('auth-email').value;
      const pass  = document.getElementById('auth-password').value;
      const { data, error } = await supabase.auth.signInWithPassword({ email, password: pass });
      if (error) {
        authStatus.textContent = 'Login failed: ' + error.message;
      } else {
        authSection.style.display = 'none';
        document.getElementById('save-ride-form').style.display = 'block';
      }
    });

    signupBtn.addEventListener('click', async () => {
      const email = document.getElementById('auth-email').value;
      const pass  = document.getElementById('auth-password').value;
      const { data, error } = await supabase.auth.signUp({ email, password: pass });
      authStatus.textContent = error
        ? 'Signup failed: ' + error.message
        : 'Signup OK! Check your email, then login above.';
    });

  // 2️⃣ Leaflet map setup (match your <div id="map">)
  const map = L.map('leaflet-map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

  // 3️⃣ GPX loader helper (Omnivore URL‐loader style)
        function loadAndDisplayGPX(url) {
          console.log('Loading GPX from', url);
          const gpxLayer = omnivore.gpx(url).on('ready', e => {
            map.fitBounds(e.target.getBounds());
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
    
    // Disable playback controls on load (but not the file picker)
    [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => {
      if (el) el.disabled = true;
    });
    // Ensure the file picker remains enabled
    uploadInput.disabled = false;


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

// — GPX upload & parsing & charting —
uploadInput.addEventListener('change', e => {
  const file = e.target.files[0];
  if (!file) return alert('No GPX file selected');

  // show “Save Ride” UI
  saveForm.style.display = 'block';

  // clear any old replay state
  if (marker)        map.removeLayer(marker);
  if (trailPolyline) map.removeLayer(trailPolyline);
  if (playInterval)  clearInterval(playInterval);
  points = [];
  breakPoints = [];

  const reader = new FileReader();
  reader.onload = ev => {
    const gpxText = ev.target.result;

    // 1️⃣ parse & draw GPX on the map
    const gpxLayer = omnivore.gpx.parse(gpxText);
    if (window.currentGPX) map.removeLayer(window.currentGPX);
    window.currentGPX = gpxLayer.addTo(map);
    map.fitBounds(gpxLayer.getBounds());

    // 2️⃣ extract trackpoints, compute speed/distance/elevation
    const xml = new DOMParser().parseFromString(gpxText, 'application/xml');
    const trkpts = Array.from(xml.getElementsByTagName('trkpt')).map(tp => ({
      lat: +tp.getAttribute('lat'),
      lng: +tp.getAttribute('lon'),
      ele: +tp.getElementsByTagName('ele')[0]?.textContent || 0,
      time: new Date(tp.getElementsByTagName('time')[0]?.textContent)
    }));
    // filter out any invalid
    points = trkpts.filter(p => p.lat && p.lng && p.time instanceof Date);
    // detect breaks & sample
    const SAMPLE = 5;
    let lastTime = points[0].time,
        lastLL   = L.latLng(points[0].lat, points[0].lng),
        accelOn  = false;
    breakPoints = [];
    // build filtered points
    const filtered = [points[0]];
    for (let i = 1; i < points.length; i++) {
      const pt = points[i],
            dt = (pt.time - lastTime) / 1000,
            moved = lastLL.distanceTo(L.latLng(pt.lat, pt.lng));
      if (dt >= SAMPLE) {
        if (dt > 180 && moved < 20) {
          breakPoints.push(filtered.length);
        } else {
          filtered.push(pt);
          lastTime = pt.time;
          lastLL   = L.latLng(pt.lat, pt.lng);
        }
      }
    }
    // always include last
    if (filtered.at(-1).time !== points.at(-1).time) {
      filtered.push(points.at(-1));
    }
    points = filtered;

    // cumulative distance & speed arrays
    cumulativeDistance = [0];
    speedData = [0];
    for (let i = 1; i < points.length; i++) {
      const a = L.latLng(points[i - 1].lat, points[i - 1].lng),
            b = L.latLng(points[i].lat,     points[i].lng),
            d = a.distanceTo(b),
            t = (points[i].time - points[i - 1].time) / 1000;
      cumulativeDistance[i] = cumulativeDistance[i - 1] + d;
      speedData[i] = t > 0 ? (d / t) * 3.6 : 0;
    }

    // 3️⃣ update summary panel
    const totalMs   = points.at(-1).time - points[0].time,
          totMin    = Math.floor(totalMs / 60000),
          rideSec   = points.reduce(
            (sum, _, i) => i > 0 && !breakPoints.includes(i)
              ? sum + ((points[i].time - points[i - 1].time) / 1000)
              : sum,
            0
          ),
          rideMin   = Math.floor(rideSec / 60),
          elevGain  = points.reduce(
            (g, p, i) => i > 0 && p.ele > points[i - 1].ele
              ? g + (p.ele - points[i - 1].ele)
              : g,
            0
          );
    distanceEl.textContent  = `${(cumulativeDistance.at(-1)/1000).toFixed(2)} km`;
    durationEl.textContent  = `${Math.floor(totMin/60)}h ${totMin%60}m`;
    rideTimeEl.textContent  = `${Math.floor(rideMin/60)}h ${rideMin%60}m`;
    elevationEl.textContent = `${elevGain.toFixed(0)} m`;

    // 4️⃣ draw the polyline and enable controls
    trailPolyline = L.polyline(
      points.map(p => [p.lat, p.lng]),
      { color: '#007bff', weight: 3, opacity: 0.7 }
    ).addTo(map).bringToBack();
    [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = false);
    slider.min = 0;
    slider.max = points.length - 1;
    slider.value = 0;
    playBtn.textContent = '▶️ Play';

    // 5️⃣ render speed filter buttons & chart
    renderSpeedFilter();
    setupChart();
    updatePlayback(0);
  };

  reader.readAsText(file);
});





  // — Controls: Play/Pause, Slider, Download summary, Save ride —
  playBtn.addEventListener('click', () => { /*…*/ });
  slider.addEventListener('input', () => { /*…*/ });
  summaryBtn.addEventListener('click', () => { /*…*/ });

  saveBtn.addEventListener('click', async (e) => {
  e.preventDefault();

  // 1️⃣ If not logged in yet, show login form and bail
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    document.getElementById('auth-section').style.display = '';
    return;
  }

  // 2️⃣ Already logged in → proceed with save logic...
  const file = document.getElementById('gpx-upload').files[0];
  if (!file) {
    document.getElementById('save-status').textContent = '❌ No GPX file selected!';
    return;
  }

  saveBtn.disabled = true;
  document.getElementById('save-status').textContent = '';

  // upload GPX...
  const timestamp = Date.now();
  const filePath  = `${user.id}/${timestamp}_${file.name}`;
  const { error: uploadError } = await supabase
    .storage
    .from('gpx-files')
    .upload(filePath, file, {
      cacheControl: '3600',
      upsert: false,
      contentType: file.type
    });

  if (uploadError) {
    saveBtn.disabled = false;
    document.getElementById('save-status').textContent = '❌ Upload failed: ' + uploadError.message;
    return;
  }

  // get public URL & insert metadata...
  const { data: { publicUrl } } = supabase
    .storage
    .from('gpx-files')
    .getPublicUrl(filePath);

  const distance_km   = parseFloat(distanceEl.textContent);
  const duration_text = durationEl.textContent;
  const [h, m]        = duration_text.match(/(\d+)h\s*(\d+)m/).slice(1);
  const duration_min  = Number(h)*60 + Number(m);
  const elevation_m   = parseInt(elevationEl.textContent);

  const { error: insertError } = await supabase
    .from('ride_logs')
    .insert([{
      user_id:      user.id,
      title:        document.getElementById('ride-title').value,
      distance_km,
      duration_min,
      elevation_m,
      gpx_path:     filePath,
      gpx_url:      publicUrl
    }]);

  saveBtn.disabled = false;
  document.getElementById('save-status').textContent = insertError
    ? '❌ Failed to save ride: ' + insertError.message
    : '✅ Ride saved!';

  if (!insertError) {
    saveForm.style.display = 'none';
    document.getElementById('ride-title').value = '';
  }
});
});
