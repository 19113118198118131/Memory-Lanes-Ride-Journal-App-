import supabase from './supabaseClient.js';

document.addEventListener('DOMContentLoaded', async () => {
  // 1️⃣ — Globals & UI refs — must come first
  let points = [];
  let marker = null, trailPolyline = null, elevationChart = null;
  let cumulativeDistance = [], speedData = [], breakPoints = [], accelData = [];
  window.playInterval = null;

  // Playback/seek helper
  window.jumpToPlaybackIndex = function(idx) {
    // Pause any running playback
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      document.getElementById('play-replay').textContent = '▶️ Play';
    }
    // Seek the slider + update UI
    document.getElementById('replay-slider').value = idx;
    window.fracIndex = idx;
    updatePlayback(idx);
  };

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

    // Elevation chart cursor
    if (elevationChart) {
      const posDs = elevationChart.data.datasets.find(d => d.label === 'Position');
      posDs.yAxisID = mode === 'speed' ? 'ySpeed' : 'yElevation';
      posDs.data[0] = { x: parseFloat(distKm), y: mode === 'speed' ? speedData[idx] : points[idx].ele };
      elevationChart.update('none');
    }

    // Acceleration chart cursor
    if (window.accelChart) {
      const accelCursor = window.accelChart.data.datasets.find(d => d.label === 'Point in Ride');
      if (accelCursor) {
        accelCursor.data[0] = { x: parseFloat(distKm), y: accelData[idx] };
        window.accelChart.update('none');
      }
    }

    document.getElementById('telemetry-elevation').textContent = `${points[idx].ele.toFixed(0)} m`;
    document.getElementById('telemetry-distance').textContent = `${distKm} km`;
    document.getElementById('telemetry-speed').textContent = `${speedData[idx].toFixed(1)} km/h`;
  };

  const FRAME_DELAY_MS = 50;
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

  // Disable controls until GPX is loaded
  [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = true);

  // Speed bins for filtering
  const speedBins = [
    { label: '50–80',  min:  50, max:  80 },
    { label: '80–100', min:  80, max: 100 },
    { label: '100–120',min: 100, max: 120 },
    { label: '120–160',min: 120, max: 160 },
    { label: '160–200',min: 160, max: 200 },
    { label: '200+',   min: 200, max: Infinity }
  ];
  let selectedSpeedBins = new Set();
  let speedHighlightLayer = null;

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

  function highlightSpeedBin(i) {
    const btn = document.querySelector(`#speed-bins .speed-bin-btn[data-index="${i}"]`);
    const isActive = selectedSpeedBins.has(i);
    if (isActive) selectedSpeedBins.delete(i); else selectedSpeedBins.add(i);
    btn.classList.toggle('active', !isActive);
    if (speedHighlightLayer) map.removeLayer(speedHighlightLayer);
    if (!selectedSpeedBins.size) {
      renderAccelChart(accelData, cumulativeDistance, speedData, [], speedBins);
      return;
    }
    const segments = [];
    for (let j=1; j<points.length; j++) {
      const sp = speedData[j];
      for (let b of selectedSpeedBins) {
        if (sp >= speedBins[b].min && sp < speedBins[b].max) {
          segments.push([
            [points[j-1].lat, points[j-1].lng],
            [points[j].lat,   points[j].lng]
          ]);
          break;
        }
      }
    }
    speedHighlightLayer = L.layerGroup(
      segments.map(seg => L.polyline(seg, { weight:5, opacity:0.8, color:'#8338ec' }))
    ).addTo(map);
    renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
  }

  // 🔁 Playback Control
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
      updatePlayback(idx);
    }, FRAME_DELAY_MS);
  });

  slider.addEventListener('input', () => {
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      playBtn.textContent = '▶️ Play';
    }
    updatePlayback(Number(slider.value));
  });

  // Initialize Leaflet map
  const map = L.map('leaflet-map').setView([20,0],2);
  setTimeout(() => map.invalidateSize(),0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

  // 2️⃣ — Load from ?ride=… if provided
  const params = new URLSearchParams(window.location.search);
  if (params.has('ride')) {
    document.getElementById('upload-section').style.display = 'none';
    const rideId = params.get('ride');
    const { data: ride, error: rideErr } = await supabase
      .from('ride_logs').select('gpx_path').eq('id',rideId).single();
    if (rideErr) return alert('Load failed: '+rideErr.message);
    const { data: urlData, error: urlErr } = supabase
      .storage.from('gpx-files').getPublicUrl(ride.gpx_path);
    if (urlErr) return alert('URL error: '+urlErr.message);
    const resp = await fetch(urlData.publicUrl);
    const gpxText = await resp.text();
    await parseAndRenderGPX(gpxText);
    saveForm.style.display = 'none';
    return;
  }

  // ... Login/signup & save-form logic remains unchanged ...

  // 0️⃣— GPX parsing & rendering
  async function parseAndRenderGPX(gpxText) {
    const xml = new DOMParser().parseFromString(gpxText, 'application/xml');
    const trkpts = Array.from(xml.getElementsByTagName('trkpt')).map(tp => ({
      lat: +tp.getAttribute('lat'),
      lng: +tp.getAttribute('lon'),
      ele: +tp.getElementsByTagName('ele')[0]?.textContent||0,
      time: new Date(tp.getElementsByTagName('time')[0]?.textContent)
    })).filter(p => p.lat && p.lng && p.time instanceof Date);
    if (!trkpts.length) return alert('No valid trackpoints');

    // Downsample every 5s, detect breaks
    const SAMPLE = 5;
    points = [trkpts[0]];
    breakPoints = [];
    let lastTime = trkpts[0].time;
    let lastLL   = L.latLng(trkpts[0].lat, trkpts[0].lng);
    for (let i=1;i<trkpts.length;i++) {
      const pt = trkpts[i];
      const dt = (pt.time - lastTime)/1000;
      const moved = lastLL.distanceTo(L.latLng(pt.lat,pt.lng));
      if (dt>=SAMPLE) {
        if (dt>180 && moved<20) breakPoints.push(points.length);
        else { points.push(pt); lastTime=pt.time; lastLL=L.latLng(pt.lat,pt.lng); }
      }
    }
    if (points.at(-1).time!==trkpts.at(-1).time) points.push(trkpts.at(-1));

    // Compute distances, speeds, accels
    cumulativeDistance=[0]; speedData=[0]; accelData=[0];
    for (let i=1;i<points.length;i++) {
      const a=L.latLng(points[i-1].lat,points[i-1].lng);
      const b=L.latLng(points[i].lat,  points[i].lng);
      const d=a.distanceTo(b);
      const t=(points[i].time - points[i-1].time)/1000;
      const v=t>0?(d/t)*3.6:0;
      cumulativeDistance[i]=cumulativeDistance[i-1]+d;
      speedData[i]=v;
      accelData[i]=t>0?(v-speedData[i-1])/t:0;
    }

    // Update summary UI
    const totalMs = points.at(-1).time - points[0].time;
    const totMin  = Math.floor(totalMs/60000);
    distanceEl.textContent = `${(cumulativeDistance.at(-1)/1000).toFixed(2)} km`;
    durationEl.textContent = `${Math.floor(totMin/60)}h ${totMin%60}m`;
    const rideSec = points.reduce((sum,_,i) =>
      i>0&&!breakPoints.includes(i)? sum+((points[i].time-points[i-1].time)/1000): sum,0);
    const rideMin = Math.floor(rideSec/60);
    rideTimeEl.textContent = `${Math.floor(rideMin/60)}h ${rideMin%60}m`;
    elevationEl.textContent = `${points.reduce((s,p,i)=> i>0&&p.ele>points[i-1].ele? s+(p.ele-points[i-1].ele):s,0).toFixed(0)} m`;

    // Draw polyline & fit map
    if (trailPolyline) map.removeLayer(trailPolyline);
    trailPolyline = L.polyline(points.map(p=>[p.lat,p.lng]), { color:'#007bff', weight:3, opacity:0.7 })
      .addTo(map).bringToBack();
    map.fitBounds(trailPolyline.getBounds(), { padding:[30,30], animate:false });

    // Build charts & enable controls
    setupChart();
    renderSpeedFilter();
    renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
    [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el=>el.disabled=false);
    slider.min=0; slider.max=points.length-1; slider.value=0;
    playBtn.textContent='▶️ Play';
  }

  // 2: ... (signup/login/upload handlers omitted for brevity) ...

  // renderAccelChart now with proper destroy guard + onClick pause-sync
  function renderAccelChart(accelData, dist, speed, selectedBins, bins) {
    const ctx = document.getElementById('accelChart')?.getContext('2d');
    if (!ctx) return;
    if (window.accelChart && typeof window.accelChart.destroy === 'function') {
      window.accelChart.destroy();
    }
    const accelPts = dist.map((x,i)=>(Number.isFinite(accelData[i])?{x:x/1000,y:accelData[i]}:null)).filter(Boolean);
    const highlightPts = dist.map((x,i)=>(selectedBins.includes(i) && Number.isFinite(speed[i])?{x:x/1000,y:speed[i],idx:i}:null)).filter(Boolean);

    const datasets=[
      { label:'Point in Ride', data:[{x:0,y:0}], type:'scatter', pointRadius:5, showLine:false, backgroundColor:'#fff', borderColor:'#fff', yAxisID:'y' },
      { label:'Acceleration', data:accelPts, borderWidth:2, showLine:true, fill:false, yAxisID:'y' },
      { label:'Highlighted Speeds', data:highlightPts, type:'scatter', pointRadius:4, yAxisID:'ySpeed' }
    ];

    window.accelChart = new Chart(ctx, {
      type:'line', data:{datasets},
      options:{
        responsive:true, animation:false,
        interaction:{mode:'nearest', intersect:false},
        onClick(evt) {
          if (window.playInterval) { clearInterval(window.playInterval); window.playInterval=null; playBtn.textContent='▶️ Play'; }
          const el = this.getElementsAtEventForMode(evt,'nearest',{intersect:false},true);
          if (!el.length) return;
          const dp = this.data.datasets[el[0].datasetIndex].data[el[0].index];
          if (dp && typeof dp.idx==='number') window.jumpToPlaybackIndex(dp.idx);
        },
        scales:{ x:{ type:'linear', title:{display:true,text:'Distance (km)'} }, y:{ position:'left', title:{display:true,text:'Accel (m/s²)'} }, ySpeed:{ position:'right', title:{display:true,text:'Speed (km/h)'} } },
        plugins:{ legend:{display:true}, tooltip:{ callbacks:{label:ctx=>`${ctx.dataset.label}: ${ctx.raw.y.toFixed(2)}`} } }
      }
    });
  }

  function setupChart() {
    const ctx = document.getElementById('elevationChart').getContext('2d');
    if (elevationChart) elevationChart.destroy();
    elevationChart = new Chart(ctx, {
      type:'line', data:{ datasets:[ /* elevation + position + breaks + speed datasets */ ] },
      options:{
        responsive:true, animation:false,
        interaction:{mode:'nearest', intersect:false},
        onClick(evt) {
          if (window.playInterval) { clearInterval(window.playInterval); window.playInterval=null; playBtn.textContent='▶️ Play'; }
          const el = this.getElementsAtEventForMode(evt,'nearest',{intersect:false},true);
          if (!el.length) return;
          const dp = this.data.datasets[el[0].datasetIndex].data[el[0].index];
          if (dp && typeof dp.idx==='number') window.jumpToPlaybackIndex(dp.idx);
        },
        // ... scales & plugins settings ...
      }
    });
  }

  // (rest of your existing signup/login/save handlers)
});
