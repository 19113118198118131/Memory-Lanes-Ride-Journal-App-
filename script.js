// script.js
import supabase from './supabaseClient.js';

console.log('script.js loaded');
window.updatePlayback = null;

document.addEventListener('DOMContentLoaded', async () => {
  // ── AUTH SETUP ──
  const { data: { user } } = await supabase.auth.getUser();
  const authSection  = document.getElementById('auth-section');
  const saveForm     = document.getElementById('save-ride-form');
  if (!user) {
    // hide Save-Ride until they authenticate
    saveForm.style.display = 'none';
  } else {
    authSection.style.display = 'none';
  }

  // Login / Sign-Up handlers
  document.getElementById('login-btn').onclick = async () => {
    const email = document.getElementById('auth-email').value;
    const pass  = document.getElementById('auth-password').value;
    const { error } = await supabase.auth.signInWithPassword({ email, password: pass });
    document.getElementById('auth-status').textContent = error
      ? 'Login failed: ' + error.message
      : '✅ Logged in!';
    if (!error) {
      authSection.style.display = 'none';
      saveForm.style.display  = 'block';
    }
  };
  document.getElementById('signup-btn').onclick = async () => {
    const email = document.getElementById('auth-email').value;
    const pass  = document.getElementById('auth-password').value;
    const { error } = await supabase.auth.signUp({ email, password: pass });
    document.getElementById('auth-status').textContent = error
      ? 'Signup failed: ' + error.message
      : '✅ Signup OK! Check email then log in.';
  };

  // ── MAP SETUP ──
  const map = L.map('map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);

  // ── GLOBALS & DOM REFS ──
  let points = [], marker = null, trailPolyline = null;
  let elevationChart = null, cumulativeDistance = [], speedData = [];
  let breakPoints = [], playInterval = null, fracIndex = 0;
  let speedHighlightLayer = null, selectedSpeedBins = new Set(), accelData = [];

  const FRAME_DELAY_MS = 50;
  const uploadInput = document.getElementById('gpx-upload');
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

  // Initially disable controls until GPX is loaded
  [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = true);

  // ── SPEED FILTER UI ──
  const speedBins = [
    { label:'50–80',  min:50,  max:80  },
    { label:'80–100', min:80,  max:100 },
    { label:'100–120',min:100, max:120 },
    { label:'120–160',min:120, max:160 },
    { label:'160–200',min:160, max:200 },
    { label:'200+',   min:200, max:Infinity }
  ];
  function renderSpeedFilter() {
    const container = document.getElementById('speed-bins');
    container.innerHTML = '';
    speedBins.forEach((bin,i) => {
      const btn = document.createElement('button');
      btn.textContent = bin.label;
      btn.classList.add('speed-bin-btn');
      btn.dataset.idx = i;
      btn.onclick = () => highlightSpeedBin(i);
      container.appendChild(btn);
    });
  }
  function highlightSpeedBin(i) {
    const btn = document.querySelector(`button[data-idx='${i}']`);
    if (selectedSpeedBins.has(i)) {
      selectedSpeedBins.delete(i);
      btn.classList.remove('active');
    } else {
      selectedSpeedBins.add(i);
      btn.classList.add('active');
    }
    if (speedHighlightLayer) map.removeLayer(speedHighlightLayer);
    if (!selectedSpeedBins.size) {
      renderAccelChart(accelData, cumulativeDistance, speedData, [], speedBins);
      return;
    }
    const segments = [];
    for (let j=1; j<points.length; j++) {
      const s = speedData[j];
      for (let b of selectedSpeedBins) {
        if (s >= speedBins[b].min && s < speedBins[b].max) {
          segments.push([[points[j-1].lat,points[j-1].lng],
                          [points[j].lat,  points[j].lng]]);
          break;
        }
      }
    }
    speedHighlightLayer = L.layerGroup(
      segments.map(seg => L.polyline(seg, { weight:5, opacity:0.8 }))
    ).addTo(map);
    renderAccelChart(accelData, cumulativeDistance, speedData, [...selectedSpeedBins], speedBins);
  }

  // ── PLAYBACK & CHART SETUP ──
  window.updatePlayback = idx => {
    const p = points[idx];
    if (!marker) {
      marker = L.circleMarker([p.lat,p.lng], { radius:6 }).addTo(map);
    } else {
      marker.setLatLng([p.lat,p.lng]);
    }
    trailPolyline.setLatLngs(points.slice(0, idx+1).map(pt=>[pt.lat,pt.lng]));
    map.panTo([p.lat,p.lng], { animate:false });

    // update telemetry overlay
    document.getElementById('telemetry-elevation').textContent = `${p.ele.toFixed(0)} m`;
    document.getElementById('telemetry-distance').textContent  = `${(cumulativeDistance[idx]/1000).toFixed(2)} km`;
    document.getElementById('telemetry-speed').textContent     = `${speedData[idx].toFixed(1)} km/h`;

    // update position dot on elevationChart
    const mode = document.querySelector('input[name="chartMode"]:checked').value;
    const ds = elevationChart.data.datasets.find(d=>d.label==='Position');
    ds.yAxisID = mode==='speed' ? 'ySpeed' : 'yElevation';
    ds.data[0] = { x: cumulativeDistance[idx]/1000,
                   y: mode==='speed' ? speedData[idx] : p.ele };
    elevationChart.update('none');

    slider.value = idx;
  };

  function setupChart() {
    const ctx = document.getElementById('elevationChart').getContext('2d');
    if (elevationChart) elevationChart.destroy();
    elevationChart = new Chart(ctx, {
      type:'line',
      data:{
        datasets:[
          {
            label:'Elevation',
            data: points.map((p,i)=>({ x: cumulativeDistance[i]/1000, y: p.ele })),
            borderColor:'#64ffda', fill:true, tension:0.3, yAxisID:'yElevation'
          },
          {
            label:'Speed (km/h)',
            data: points.map((p,i)=>({ x: cumulativeDistance[i]/1000, y: speedData[i] })),
            borderColor:'#ff6384', fill:true, tension:0.3, yAxisID:'ySpeed'
          },
          {
            label:'Position',
            data:[{ x:0,y:points[0]?.ele||0 }],
            type:'scatter', pointRadius:5, showLine:false
          },
          {
            label:'Breaks',
            data: breakPoints.map(i=>({ x:cumulativeDistance[i]/1000, y: points[i].ele })),
            type:'scatter', pointRadius:3, showLine:false
          }
        ]
      },
      options:{
        animation:false,
        interaction:{ mode:'nearest', intersect:false, axis:'x' },
        scales:{
          x:{ title:{ display:true, text:'Distance (km)' } },
          yElevation:{ position:'left', title:{ text:'Elevation (m)' } },
          ySpeed:{ position:'right', title:{ text:'Speed (km/h)' } }
        },
        onClick:(_, elems)=>{
          if (elems.length) updatePlayback(elems[0].index);
        }
      }
    });
    document.querySelectorAll('input[name="chartMode"]').forEach(r => {
      r.onchange = () => setupChart();
    });
  }

  // ── GPX UPLOAD & PARSING ──
  uploadInput.onchange = e => {
    const file = e.target.files[0];
    if (!file) return alert('No GPX file selected');

    // show Save-Ride UI
    saveForm.style.display = 'block';

    // clear old playback + layers
    if (playInterval) clearInterval(playInterval);
    if (marker)        map.removeLayer(marker);
    if (trailPolyline) map.removeLayer(trailPolyline);
    points=[]; breakPoints=[]; cumulativeDistance=[]; speedData=[]; accelData=[];

    // read GPX text
    const reader = new FileReader();
    reader.onload = ev => {
      const gpxText = ev.target.result;

      // 1) add raw GPX via omnivore
      const gpxLayer = omnivore.gpx.parse(gpxText);
      if (window.currentGPX) map.removeLayer(window.currentGPX);
      window.currentGPX = gpxLayer.addTo(map);

      // 2) extract <trkpt> & do your down-sampling
      const xml = new DOMParser().parseFromString(gpxText,'application/xml');
      const rawPts = Array.from(xml.getElementsByTagName('trkpt')).map(tp=>({
        lat:+tp.getAttribute('lat'),
        lng:+tp.getAttribute('lon'),
        ele:+tp.getElementsByTagName('ele')[0]?.textContent||0,
        time:new Date(tp.getElementsByTagName('time')[0]?.textContent)
      })).filter(p=>p.lat&&p.lng&&p.time instanceof Date);

      if (!rawPts.length) return alert('No valid trackpoints found');
      const SAMPLE = 5;
      let lastTime=rawPts[0].time, lastLL=L.latLng(rawPts[0].lat,rawPts[0].lng);
      points.push(rawPts[0]);
      for (let i=1;i<rawPts.length;i++){
        const pt=rawPts[i],
              dt=(pt.time-lastTime)/1000,
              moved=lastLL.distanceTo(L.latLng(pt.lat,pt.lng));
        if (dt>=SAMPLE){
          if (dt>180 && moved<20){
            breakPoints.push(points.length);
          } else {
            points.push(pt);
            lastTime=pt.time;
            lastLL=L.latLng(pt.lat,pt.lng);
          }
        }
      }
      if (points.at(-1).time !== rawPts.at(-1).time) {
        points.push(rawPts.at(-1));
      }

      // 3) compute distances & speeds
      cumulativeDistance=[0];
      speedData=[0];
      for (let i=1;i<points.length;i++){
        const a=L.latLng(points[i-1].lat,points[i-1].lng),
              b=L.latLng(points[i].lat,  points[i].lng),
              d=a.distanceTo(b),
              t=(points[i].time-points[i-1].time)/1000;
        cumulativeDistance[i]=cumulativeDistance[i-1]+d;
        speedData[i]         = t>0?(d/t)*3.6:0;
      }

      // 4) fill Ride Summary
      const totalMs = points.at(-1).time - points[0].time,
            totMin  = Math.floor(totalMs/60000),
            rideSec = points.reduce((sum,_,i)=>
              i>0&&!breakPoints.includes(i)
                ? sum+((points[i].time-points[i-1].time)/1000)
                : sum
            ,0),
            rideMin = Math.floor(rideSec/60);
      durationEl.textContent  = `${Math.floor(totMin/60)}h ${totMin%60}m`;
      rideTimeEl.textContent  = `${Math.floor(rideMin/60)}h ${rideMin%60}m`;
      distanceEl.textContent  = `${(cumulativeDistance.at(-1)/1000).toFixed(2)} km`;
      elevationEl.textContent = `${points.reduce((s,p,i)=>
        i>0&&p.ele>points[i-1].ele
          ? s+(p.ele-points[i-1].ele)
          : s
      ,0).toFixed(0)} m`;

      // 5) draw the simplified polyline
      if (trailPolyline) map.removeLayer(trailPolyline);
      trailPolyline = L.polyline(
        points.map(p=>[p.lat,p.lng]),
        { color:'#007bff', weight:3, opacity:0.7 }
      ).addTo(map).bringToBack();
      map.fitBounds(trailPolyline.getBounds(), { padding:[30,30], animate:false });

      // 6) enable controls & build charts/analytics
      setupChart();
      renderSpeedFilter();
      [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el=>el.disabled=false);
      slider.min = 0; slider.max = points.length-1; slider.value = 0;
      playBtn.textContent = '▶️ Play';
      if (window.Analytics) Analytics.initAnalytics(points, speedData, cumulativeDistance);
    };

    reader.readAsText(file);
  };

  // ── PLAY / PAUSE & SLIDER ──
  playBtn.onclick = () => {
    if (!points.length) return;
    if (playInterval) {
      clearInterval(playInterval);
      playInterval = null;
      playBtn.textContent = '▶️ Play';
      return;
    }
    fracIndex = +slider.value;
    playBtn.textContent = '⏸ Pause';
    const speedMult = parseFloat(speedSel.value)||1;
    playInterval = setInterval(()=>{
      fracIndex += speedMult;
      const idx = Math.floor(fracIndex);
      if (idx >= points.length) {
        clearInterval(playInterval);
        playInterval = null;
        playBtn.textContent = '🔁 Replay';
      } else {
        updatePlayback(idx);
      }
    }, FRAME_DELAY_MS);
  };
  slider.oninput = () => {
    if (playInterval) {
      clearInterval(playInterval);
      playInterval = null;
      playBtn.textContent = '▶️ Play';
    }
    updatePlayback(+slider.value);
  };

  // ── DOWNLOAD SUMMARY ──
  summaryBtn.onclick = () => {
    const txt = `Distance: ${distanceEl.textContent}\n` +
                `Total Duration: ${durationEl.textContent}\n` +
                `Ride Time: ${rideTimeEl.textContent}\n` +
                `Elevation Gain: ${elevationEl.textContent}`;
    const blob = new Blob([txt], { type:'text/plain' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'ride-summary.txt';
    a.click();
  };

  // ── SAVE RIDE (requires login) ──
  saveBtn.onclick = async () => {
    const title = document.getElementById('ride-title').value;
    const { data:{user}, error:usrErr } = await supabase.auth.getUser();
    if (!user) {
      // prompt login
      authSection.style.display = '';
      return;
    }
    // insert into ride_logs…
    const distKm  = parseFloat(distanceEl.textContent);
    const [h,m]   = durationEl.textContent.match(/(\d+)h\s*(\d+)m/).slice(1);
    const durMin  = +h*60 + +m;
    const elevM   = parseInt(elevationEl.textContent,10);
    const { error } = await supabase
      .from('ride_logs')
      .insert([{ user_id:user.id, title, distance_km:distKm, duration_min:durMin, elevation_m:elevM }]);
    document.getElementById('save-status').textContent = error
      ? '❌ Failed: '+error.message
      : '✅ Ride saved!';
    if (!error) {
      saveForm.style.display = 'none';
    }
  };
});
