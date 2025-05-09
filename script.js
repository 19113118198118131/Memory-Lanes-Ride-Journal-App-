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

function setupChart(){
    const ctx=document.getElementById('elevationChart').getContext('2d');
    if(elevationChart) elevationChart.destroy();
    elevationChart=new Chart(ctx,{type:'line',data:{datasets:[
      {label:'Elevation',data:points.map((p,i)=>({x:cumulativeDistance[i]/1000,y:p.ele})),"borderColor":'#64ffda',"backgroundColor":(()=>{const g=ctx.createLinearGradient(0,0,0,200);g.addColorStop(0,'rgba(100,255,218,0.5)');g.addColorStop(1,'rgba(10,25,47,0.1)');return g;})(),borderWidth:2,tension:0.3,pointRadius:0,fill:true,yAxisID:'yElevation'},
      {label:'Position',type:'scatter',data:[{x:0,y:points[0]?points[0].ele:0}],pointRadius:5,pointBackgroundColor:'#fff',showLine:false,yAxisID:'yElevation'},
      {label:'Breaks',type:'scatter',data:breakPoints.map(i=>({x:cumulativeDistance[i]/1000,y:points[i].ele})),pointRadius:3,pointBackgroundColor:'rgba(150,150,150,0.6)',showLine:false,yAxisID:'yElevation'},
      {label:'Speed (km/h)',data:points.map((p,i)=>({x:cumulativeDistance[i]/1000,y:speedData[i]})),borderColor:'#ff6384',backgroundColor:'rgba(255,99,132,0.1)',borderWidth:2,tension:0.3,pointRadius:0,fill:true,yAxisID:'ySpeed'}
    ]},options:{responsive:true,animation:false,interaction:{mode:'nearest',intersect:false,axis:'x'},onClick:(evt,elems)=>{if(elems.length)updatePlayback(elems[0].index);},scales:{x:{type:'linear',title:{display:true,text:'Distance (km)'},grid:{color:'#223'},ticks:{callback:v=>v.toFixed(2)}},yElevation:{display:true,position:'left',title:{display:true,text:'Elevation (m)'},grid:{color:'#334'}},ySpeed:{display:true,position:'right',title:{display:true,text:'Speed (km/h)'},grid:{drawOnChartArea:false}}},plugins:{legend:{display:true},tooltip:{callbacks:{label:ctx=>`${ctx.dataset.label}: ${ctx.raw.y.toFixed(1)}`}}}}});
    document.querySelectorAll('input[name="chartMode"]').forEach(radio=>radio.addEventListener('change',()=>{
      const mode=document.querySelector('input[name="chartMode"]:checked').value;
      elevationChart.data.datasets.forEach(ds=>{ds.hidden=(ds.label==='Elevation'||ds.label==='Breaks')?mode==='speed':ds.label==='Speed (km/h)'?mode==='elevation':false;});
      elevationChart.options.scales.yElevation.display=mode!=='speed';
      elevationChart.options.scales.ySpeed.display=mode!=='elevation';
      elevationChart.update();
    }));
  }

  // GPX load & parsing
  uploadInput.addEventListener('change',e=>{
    document.getElementById('save-ride-form').style.display='block';
    const file=e.target.files[0];if(!file)return;
    if(playInterval)clearInterval(playInterval);
    if(marker)map.removeLayer(marker);
    if(trailPolyline)map.removeLayer(trailPolyline);
    points=[];breakPoints=[];
    const reader=new FileReader();
    reader.onload=ev=>{
      const xml=new DOMParser().parseFromString(ev.target.result,'application/xml');
      const trkpts=Array.from(xml.getElementsByTagName('trkpt')).map(tp=>({lat:+tp.getAttribute('lat'),lng:+tp.getAttribute('lon'),ele:+tp.getElementsByTagName('ele')[0]?.textContent||0,time:new Date(tp.getElementsByTagName('time')[0]?.textContent)})).filter(p=>p.lat&&p.lng&&p.time instanceof Date);
      if(!trkpts.length) return alert('No valid trackpoints found');
      const SAMPLE=5;let lastTime=trkpts[0].time,lastLL=L.latLng(trkpts[0].lat,trkpts[0].lng);
      points.push(trkpts[0]);
      for(let i=1;i<trkpts.length;i++){const pt=trkpts[i];const dt=(pt.time-lastTime)/1000;const moved=lastLL.distanceTo(L.latLng(pt.lat,pt.lng));
        if(dt>=SAMPLE){if(dt>180&&moved<20)breakPoints.push(points.length);
        else{points.push(pt);lastTime=pt.time;lastLL=L.latLng(pt.lat,pt.lng);}}
      }
      if(points.at(-1).time!==trkpts.at(-1).time) points.push(trkpts.at(-1));
      cumulativeDistance=[0];speedData=[0];
      for(let i=1;i<points.length;i++){const a=L.latLng(points[i-1].lat,points[i-1].lng),b=L.latLng(points[i].lat,points[i].lng),d=a.distanceTo(b),t=(points[i].time-points[i-1].time)/1000;cumúla


// Play/Pause
playBtn.addEventListener('click', () => {
  if (!points.length) return;
  // if already playing, stop
  if (playInterval) {
    clearInterval(playInterval);
    playInterval = null;
    playBtn.textContent = '▶️ Play';
    return;
  }
  // if we’re at the end, reset to start
  if (playBtn.textContent === '🔁 Replay') {
    slider.value = 0;
    updatePlayback(0);
    fracIndex = 0;
  } else {
    // resume from current slider position
    fracIndex = Number(slider.value);
  }
  playBtn.textContent = '⏸ Pause';
  const speedMultiplier = parseFloat(speedSel.value) || 1;
  playInterval = setInterval(() => {
    fracIndex += speedMultiplier;
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

// Save ride
document.getElementById('save-ride-btn').addEventListener('click', async () => {
  const title = document.getElementById('ride-title').value;
  const distance_km = parseFloat(distanceEl.textContent);
  const [h, m] = document.getElementById('duration')
                   .textContent.match(/(\d+)h\s*(\d+)m/)
                   .slice(1).map(Number);
  const duration_min = h*60 + m;
  const elevation_m = parseInt(elevationEl.textContent, 10);

  // ensure user is logged in
  const { data: { user }, error: userErr } = await supabase.auth.getUser();
  if (userErr || !user) {
    return document.getElementById('save-status')
           .textContent = 'User not logged in!';
  }

  // grab the GPX file
  const file = document.getElementById('gpx-upload').files[0];
  if (!file) {
    return document.getElementById('save-status')
           .textContent = 'No GPX file to save!';
  }

  // upload to storage
  const timestamp = Date.now();
  const filename = `${user.id}/${timestamp}-${file.name}`;
  const { error: uploadErr } = await supabase
    .storage
    .from('gpx-files')
    .upload(filename, file, { cacheControl: '3600', upsert: false });
  if (uploadErr) {
    document.getElementById('save-status')
      .textContent = '❌ Upload failed: ' + uploadErr.message;
    return;
  }

  // insert metadata
  const { error: insertErr } = await supabase
    .from('ride_logs')
    .insert([{
      user_id:     user.id,
      title,
      distance_km,
      duration_min,
      elevation_m,
      gpx_path:    filename
    }]);
  
  document.getElementById('save-status').textContent = insertErr
    ? '❌ Save failed: ' + insertErr.message
    : '✅ Ride saved successfully!';

  if (!insertErr) {
    document.getElementById('save-ride-form').style.display = 'none';
    document.getElementById('ride-title').value = '';
  }
});

});
