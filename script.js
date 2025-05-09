// script.js
import supabase from './supabaseClient.js';

console.log('script.js loaded');
window.updatePlayback = null;

document.addEventListener('DOMContentLoaded', async () => {
  // 1️⃣ Auth check: kick out to login if not signed in
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) {
    console.error('Not logged in:', userError);
    // hide ride form and redirect
    document.getElementById('save-ride-form').style.display = 'none';
    return window.location.href = 'index.html';
  }

  // 2️⃣ Leaflet map setup
  const map = L.map('map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

  // 3️⃣ Helper to fetch & render GPX
  async function loadAndDisplayGPX(url) {
    try {
      console.log('Loading GPX from', url);
      const res  = await fetch(url);
      if (!res.ok) throw new Error(res.statusText);
      const text = await res.text();
      const gpxLayer = omnivore.gpx.parse(text);
      if (window.currentGPX) map.removeLayer(window.currentGPX);
      window.currentGPX = gpxLayer.addTo(map);
      map.fitBounds(gpxLayer.getBounds());
      if (typeof renderChartsFromGPXText === 'function') {
        renderChartsFromGPXText(text);
      }
    } catch (err) {
      console.error('GPX load error:', err);
    }
  }

  // 4️⃣ Auto-load a ride if navigated from dashboard
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
    } else if (data) {
      // populate UI
      document.getElementById('ride-title').value   = data.title;
      document.getElementById('save-ride-form').style.display = 'block';
      document.getElementById('distance').textContent  = `${data.distance_km.toFixed(2)} km`;
      document.getElementById('duration').textContent  = `${data.duration_min} min`;
      document.getElementById('elevation').textContent = `${data.elevation_m} m`;

      // render on map
      if (data.gpx_url) {
        await loadAndDisplayGPX(data.gpx_url);
      }
    }
  }


  // — Globals & DOM refs —
  let points = [], marker = null, trailPolyline = null;
  let elevationChart = null, cumulativeDistance = [], speedData = [];
  let breakPoints = [], playInterval = null, fracIndex = 0;
  let speedHighlightLayer = null, selectedSpeedBins = new Set(), accelData = [];

  const FRAME_DELAY_MS = 50;
  const distanceEl = document.getElementById('distance');
  const durationEl = document.getElementById('duration');
  const rideTimeEl = document.getElementById('ride-time');
  const elevationEl = document.getElementById('elevation');
  const slider = document.getElementById('replay-slider');
  const playBtn = document.getElementById('play-replay');
  const summaryBtn = document.getElementById('download-summary');
  const videoBtn = document.getElementById('export-video');
  const speedSel = document.getElementById('playback-speed');
  const uploadInput = document.getElementById('gpx-upload');
  [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = true);

  // … rest of existing handlers & functions (uploadInput.onchange, playBtn.onclick, etc.) …
});

  
  // — Globals & DOM refs —
  let points = [],
      marker = null,
      trailPolyline = null,
      elevationChart = null,
      cumulativeDistance = [],
      speedData = [],
      breakPoints = [],
      playInterval = null,
      fracIndex = 0,
      speedHighlightLayer = null,
      selectedSpeedBins = new Set(),
      accelData = [];



  const FRAME_DELAY_MS = 50;  // 20 fps
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

  if (isActive) {
    selectedSpeedBins.delete(binIndex);
    btn.classList.remove('active');
  } else {
    selectedSpeedBins.add(binIndex);
    btn.classList.add('active');
  }

  if (speedHighlightLayer) {
    map.removeLayer(speedHighlightLayer);
    speedHighlightLayer = null;
  }

  if (selectedSpeedBins.size === 0) {
    renderAccelChart(window.accelData, cumulativeDistance, speedData, [], speedBins);
    return;
  }

  const segments = [];
  for (let i = 1; i < points.length; i++) {
    const s = speedData[i];
    for (let binIdx of selectedSpeedBins) {
      const { min, max } = speedBins[binIdx];
      if (s >= min && s < max) {
        segments.push([[points[i - 1].lat, points[i - 1].lng], [points[i].lat, points[i].lng]]);
        break;
      }
    }
  }

  speedHighlightLayer = L.layerGroup(
    segments.map(seg => {
      const pl = L.polyline(seg, { color: '#8338ec', weight: 5, opacity: 0.8 });
      pl.on('add', () => { if (pl._path) pl._path.classList.add('pulse-line'); });
      return pl;
    })
  ).addTo(map);

  // ✅ FIXED LINE
  renderAccelChart(window.accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
}




  function updatePlayback(idx) {
    const p = points[idx];
    if (!marker) {
      marker = L.circleMarker([p.lat, p.lng], { radius:6, color:'#007bff', fillColor:'#007bff', fillOpacity:0.9 }).addTo(map);
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

    // Chart mode toggles
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

  // GPX load & parsing
  uploadInput.addEventListener('change', e => {
    // Show title input
document.getElementById('save-ride-form').style.display = 'block';
const file = e.target.files[0]; if (!file) return;
    if (playInterval) clearInterval(playInterval);
    if (marker) map.removeLayer(marker);
    if (trailPolyline) map.removeLayer(trailPolyline);
    points = []; breakPoints = [];
    const reader = new FileReader();
    reader.onload = ev => {
      const xml = new DOMParser().parseFromString(ev.target.result, 'application/xml');
      const trkpts = Array.from(xml.getElementsByTagName('trkpt')).map(tp => ({
        lat:+tp.getAttribute('lat'), lng:+tp.getAttribute('lon'),
        ele:+tp.getElementsByTagName('ele')[0]?.textContent||0,
        time:new Date(tp.getElementsByTagName('time')[0]?.textContent)
      })).filter(p => p.lat && p.lng && p.time instanceof Date);
      if (!trkpts.length) return alert('No valid trackpoints found');
      const SAMPLE=5; let lastTime=trkpts[0].time, lastLL=L.latLng(trkpts[0].lat,trkpts[0].lng);
      points.push(trkpts[0]);
      for (let i=1;i<trkpts.length;i++){const pt=trkpts[i],dt=(pt.time-lastTime)/1000,moved=lastLL.distanceTo(L.latLng(pt.lat,pt.lng));if(dt>=SAMPLE){if(dt>180&&moved<20) breakPoints.push(points.length);else{points.push(pt);lastTime=pt.time;lastLL=L.latLng(pt.lat,pt.lng);}}}
      if(points.at(-1).time!==trkpts.at(-1).time) points.push(trkpts.at(-1));
      cumulativeDistance=[0]; speedData=[0];
      for(let i=1;i<points.length;i++){const a=L.latLng(points[i-1].lat,points[i-1].lng),b=L.latLng(points[i].lat,points[i].lng),d=a.distanceTo(b),t=(points[i].time-points[i-1].time)/1000;cumulativeDistance[i]=cumulativeDistance[i-1]+d;speedData[i]=t>0?(d/t)*3.6:0;}
      const totalMs=points.at(-1).time-points[0].time,totMin=Math.floor(totalMs/60000);
      const rideSec=points.reduce((sum,_,i)=>i>0&&!breakPoints.includes(i)?sum+((points[i].time-points[i-1].time)/1000):sum,0),rideMin=Math.floor(rideSec/60);
      durationEl.textContent=`${Math.floor(totMin/60)}h ${totMin%60}m`;
      rideTimeEl.textContent=`${Math.floor(rideMin/60)}h ${rideMin%60}m`;
      distanceEl.textContent=`${(cumulativeDistance.at(-1)/1000).toFixed(2)} km`;
      elevationEl.textContent=`${points.reduce((sum,p,i)=>i>0&&p.ele>points[i-1].ele?sum+(p.ele-points[i-1].ele):sum,0).toFixed(0)} m`;
      trailPolyline=L.polyline(points.map(p=>[p.lat,p.lng]),{color:'#007bff',weight:3,opacity:0.7}).addTo(map).bringToBack();
      map.fitBounds(trailPolyline.getBounds(),{padding:[30,30],animate:false});
      setupChart();
      [slider,playBtn,summaryBtn,videoBtn,speedSel].forEach(el=>el.disabled=false);
      slider.min=0;slider.max=points.length-1;slider.value=0;playBtn.textContent='▶️ Play';
      renderSpeedFilter();
      if(window.Analytics) Analytics.initAnalytics(points,speedData,cumulativeDistance);
    };
    reader.readAsText(file);
  });

  // Play/Pause
  playBtn.addEventListener('click',()=>{
    if(!points.length) return;
    if(playInterval){ clearInterval(playInterval); playInterval=null; playBtn.textContent='▶️ Play'; return; }
    if(playBtn.textContent==='🔁 Replay'){ slider.value=0; updatePlayback(0); fracIndex=0; }
    else{ fracIndex=Number(slider.value); }
    playBtn.textContent='⏸ Pause';
    const mult=parseFloat(speedSel.value)||1;
    playInterval=setInterval(()=>{
      fracIndex+=mult;
      const idx=Math.floor(fracIndex);
      if(idx>=points.length){ clearInterval(playInterval); playInterval=null; playBtn.textContent='🔁 Replay'; return; }
      updatePlayback(idx);
    }, FRAME_DELAY_MS);
  });

  // Slider scrub
  slider.addEventListener('input',()=>{
    if(playInterval){ clearInterval(playInterval); playInterval=null; playBtn.textContent='▶️ Play'; }
    updatePlayback(Number(slider.value));
  });

  // Download summary
  summaryBtn.addEventListener('click',()=>{
    const txt = `Distance: ${distanceEl.textContent}\nTotal Duration: ${durationEl.textContent}\nRide Time: ${rideTimeEl.textContent}\nElevation Gain: ${elevationEl.textContent}`;
    const blob = new Blob([txt],{type:'text/plain'});
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download='ride-summary.txt';
    a.click();

});
   
document.getElementById('save-ride-btn').addEventListener('click', async () => {
  const file = document.getElementById('gpx-upload').files[0];
  if (!file) {
    document.getElementById('save-status').textContent = '❌ No GPX file selected!';
    return;
  }

  // 1️⃣ Get the user
  const {
    data: { user },
    error: userError
  } = await supabase.auth.getUser();
  if (userError || !user) {
    document.getElementById('save-status').textContent = 'User not logged in!';
    return;
  }

  const saveBtn = document.getElementById('save-ride-btn');
  saveBtn.disabled = true;

  // 2️⃣ Upload the GPX file
  // Build a unique path: "userId/timestamp_filename.gpx"
  const timestamp = Date.now();
  const fileExt   = file.name.split('.').pop();
  const filePath  = `${user.id}/${timestamp}_${file.name}`;

  const { data: uploadData, error: uploadError } = 
    await supabase
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

  // 3️⃣ (Optionally) get a public URL
  const { data: { publicUrl } } = supabase
    .storage
    .from('gpx-files')
    .getPublicUrl(filePath);

  // 4️⃣ Insert metadata + storage path into ride_logs
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
      gpx_path:     filePath,     // for backend reference
      gpx_url:      publicUrl     // for direct download/sharing
    }]);

  saveBtn.disabled = false;
  document.getElementById('save-status').textContent = insertError
    ? '❌ Failed to save ride: ' + insertError.message
    : '✅ Ride saved!';

  if (!insertError) {
    document.getElementById('save-ride-form').style.display = 'none';
    document.getElementById('ride-title').value = '';
  }
});


