// ===============================
// Memory Lanes Ride Journal - ride-live.js
// Record a ride live: GPS track, distance/speed/elapsed telemetry,
// pause/resume, then save it as a ride log. With a ?route= param, it
// also follows a planned route (position vs. the plan). Without one,
// it's a plain "start riding now" recorder — plan later, or not at all.
// ===============================

import supabase from './supabaseClient.js';

const ON_ROUTE_M = 60; // metres: within this of the planned line counts as "on route"

// ---------- DOM references ----------
const loadingEl       = document.getElementById('live-loading');
const bodyEl          = document.getElementById('live-body');
const liveTitleEl     = document.getElementById('live-title');
const routeTitleEl    = document.getElementById('live-route-title');
const statusBanner    = document.getElementById('live-status-banner');
const distanceEl      = document.getElementById('live-distance');
const elapsedEl       = document.getElementById('live-elapsed');
const speedEl         = document.getElementById('live-speed');
const onRouteCard     = document.getElementById('live-onroute-card');
const routeStatusEl   = document.getElementById('live-route-status');
const startBtn        = document.getElementById('live-start-btn');
const pauseBtn        = document.getElementById('live-pause-btn');
const finishBtn       = document.getElementById('live-finish-btn');
const recenterBtn     = document.getElementById('live-recenter-btn');
const cancelBtn       = document.getElementById('live-cancel-btn');
const saveForm        = document.getElementById('live-save-form');
const rideTitleInput  = document.getElementById('live-ride-title');
const saveBtn         = document.getElementById('live-save-btn');
const saveStatusEl    = document.getElementById('live-save-status');

// ---------- Utilities ----------
function escapeGpx(str) {
  return String(str).replace(/[<>&"]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
}
function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000, toR = Math.PI / 180;
  const dLat = (lat2 - lat1) * toR, dLng = (lng2 - lng1) * toR;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * toR) * Math.cos(lat2 * toR) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
function sampleArr(arr, maxPoints) {
  if (arr.length <= maxPoints) return arr;
  const step = (arr.length - 1) / (maxPoints - 1);
  const out = [];
  for (let i = 0; i < maxPoints; i++) out.push(arr[Math.round(i * step)]);
  return out;
}

// ---------- State ----------
let map = null;
let plannedRoute = null;       // null when recording a free (unplanned) ride
let plannedRouteSample = [];
let liveMarker = null;
let recordedLine = null;
let recordedPoints = [];
let totalDistanceM = 0;
let startTime = null;
let watchId = null;
let followMode = true;
let recording = false; // true from Start until Finish (stays true while paused)
let watching = false;  // true only while the GPS watch is actively running
let wakeLock = null;

// ---------- Init ----------
(async () => {
  const params = new URLSearchParams(window.location.search);
  const routeId = params.get('route');

  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    loadingEl.textContent = 'Please log in to record a ride.';
    return;
  }

  if (routeId) {
    const { data: route, error } = await supabase
      .from('planned_routes')
      .select('id, title, route')
      .eq('id', routeId)
      .eq('user_id', user.id)
      .single();

    if (error || !route || !Array.isArray(route.route) || route.route.length < 2) {
      loadingEl.textContent = 'Could not load that route. Go back and try again.';
      return;
    }

    plannedRoute = route;
    plannedRouteSample = sampleArr(route.route, 150);
    liveTitleEl.textContent = 'Follow Route';
    routeTitleEl.textContent = `Following: ${route.title}`;
  } else {
    liveTitleEl.textContent = 'Record a Ride';
    routeTitleEl.textContent = "Recording a free ride — no plan needed. You can edit or crop the track afterwards from Logs.";
    onRouteCard.style.display = 'none';
  }

  loadingEl.style.display = 'none';
  bodyEl.style.display = '';

  initMap();
})();

function initMap() {
  map = L.map('live-map', { zoomControl: true });
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);

  if (plannedRoute) {
    const plannedLine = L.polyline(plannedRoute.route, {
      color: '#ffd166', weight: 5, opacity: 0.85, dashArray: '10,8'
    }).addTo(map);
    map.fitBounds(plannedLine.getBounds(), { padding: [40, 40] });
  } else {
    map.setView([20, 0], 2);
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        pos => map.setView([pos.coords.latitude, pos.coords.longitude], 13),
        () => {},
        { timeout: 4000 }
      );
    }
  }

  map.on('dragstart', () => { followMode = false; recenterBtn.style.display = recording ? '' : 'none'; });
}

// ---------- Recording ----------
startBtn.addEventListener('click', startRide);
pauseBtn.addEventListener('click', togglePause);
finishBtn.addEventListener('click', finishRide);
recenterBtn.addEventListener('click', () => {
  followMode = true;
  recenterBtn.style.display = 'none';
  if (recordedPoints.length) map.panTo([recordedPoints.at(-1).lat, recordedPoints.at(-1).lng]);
});
cancelBtn.addEventListener('click', () => {
  if (recording && !confirm('Stop tracking and leave without saving?')) return;
  endWatch();
  recording = false;
  window.location.href = plannedRoute ? 'planner.html' : 'dashboard.html';
});

function startRide() {
  if (!navigator.geolocation) {
    alert('Geolocation is not supported on this device or browser.');
    return;
  }
  recordedPoints = [];
  totalDistanceM = 0;
  startTime = new Date();
  recording = true;
  followMode = true;
  beginWatch();

  startBtn.style.display = 'none';
  pauseBtn.style.display = '';
  pauseBtn.textContent = 'Pause';
  finishBtn.style.display = '';
  statusBanner.textContent = 'Recording your ride…';
}

function togglePause() {
  if (watching) {
    endWatch();
    pauseBtn.textContent = 'Resume';
    statusBanner.textContent = 'Paused. Distance and time stop counting until you resume.';
  } else {
    beginWatch();
    pauseBtn.textContent = 'Pause';
    statusBanner.textContent = 'Recording your ride…';
  }
}

function beginWatch() {
  watchId = navigator.geolocation.watchPosition(onPosition, onPositionError, {
    enableHighAccuracy: true, maximumAge: 2000, timeout: 15000
  });
  watching = true;
  requestWakeLock();
}

function endWatch() {
  if (watchId != null) navigator.geolocation.clearWatch(watchId);
  watchId = null;
  watching = false;
  releaseWakeLock();
}

function onPosition(pos) {
  const { latitude, longitude, altitude, speed } = pos.coords;
  const pt = { lat: latitude, lng: longitude, ele: altitude || 0, time: new Date(pos.timestamp) };

  if (recordedPoints.length) {
    const prev = recordedPoints[recordedPoints.length - 1];
    totalDistanceM += haversineMeters(prev.lat, prev.lng, pt.lat, pt.lng);
  }
  recordedPoints.push(pt);

  if (!liveMarker) {
    liveMarker = L.circleMarker([pt.lat, pt.lng], {
      radius: 8, color: '#64ffda', weight: 3, fillColor: '#64ffda', fillOpacity: 0.9
    }).addTo(map);
  } else {
    liveMarker.setLatLng([pt.lat, pt.lng]);
  }
  if (!recordedLine) {
    recordedLine = L.polyline([[pt.lat, pt.lng]], { color: '#00c6ff', weight: 4, opacity: 0.9 }).addTo(map);
  } else {
    recordedLine.addLatLng([pt.lat, pt.lng]);
  }
  if (followMode) map.panTo([pt.lat, pt.lng]);

  updateTelemetry(pt, speed);
}

function onPositionError(err) {
  statusBanner.textContent = `Location error: ${err.message}. Check location permissions and try again.`;
}

function updateTelemetry(pt, speedMs) {
  distanceEl.textContent = `${(totalDistanceM / 1000).toFixed(2)} km`;

  const elapsedMin = Math.max(0, Math.floor((pt.time - startTime) / 60000));
  elapsedEl.textContent = `${Math.floor(elapsedMin / 60)}h ${elapsedMin % 60}m`;

  const kmh = speedMs != null && Number.isFinite(speedMs) ? speedMs * 3.6 : null;
  speedEl.textContent = kmh != null ? `${kmh.toFixed(0)} km/h` : '–';

  if (!plannedRoute) return;
  let minD = Infinity;
  for (const [plat, plng] of plannedRouteSample) {
    const d = haversineMeters(pt.lat, pt.lng, plat, plng);
    if (d < minD) minD = d;
  }
  const onRoute = minD < ON_ROUTE_M;
  routeStatusEl.textContent = onRoute ? 'On route' : `Off by ${Math.round(minD)} m`;
  routeStatusEl.classList.toggle('on-route', onRoute);
  routeStatusEl.classList.toggle('off-route', !onRoute);
}

function finishRide() {
  endWatch();
  recording = false;
  if (recordedPoints.length < 2) {
    statusBanner.textContent = 'Not enough GPS points were recorded to save this ride.';
    startBtn.style.display = '';
    pauseBtn.style.display = 'none';
    finishBtn.style.display = 'none';
    return;
  }
  pauseBtn.style.display = 'none';
  finishBtn.style.display = 'none';
  recenterBtn.style.display = 'none';
  statusBanner.textContent = 'Ride recorded. Save it below to keep it.';
  saveForm.style.display = '';
  rideTitleInput.value = plannedRoute
    ? `${plannedRoute.title} — ${new Date().toLocaleDateString()}`
    : `Ride — ${new Date().toLocaleDateString()}`;
}

// ---------- Wake lock (best-effort, keeps the screen on while recording) ----------
async function requestWakeLock() {
  try {
    if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen');
  } catch (e) { /* non-critical: recording still works, screen may just sleep */ }
}
function releaseWakeLock() {
  if (wakeLock) { wakeLock.release().catch(() => {}); wakeLock = null; }
}
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && watching) requestWakeLock();
});

// ---------- Save recorded ride ----------
function buildTrackGPX(pts, title) {
  const trkpts = pts.map(p =>
    `<trkpt lat="${p.lat}" lon="${p.lng}"><ele>${p.ele || 0}</ele><time>${p.time.toISOString()}</time></trkpt>`
  ).join('\n        ');
  return `<?xml version="1.0"?>
<gpx version="1.1" creator="Memory Lanes Ride Journal" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>${escapeGpx(title)}</name>
    <trkseg>
        ${trkpts}
    </trkseg>
  </trk>
</gpx>`;
}

function setSaveStatus(msg, isError) {
  saveStatusEl.textContent = msg;
  saveStatusEl.style.color = isError ? 'var(--color-danger)' : 'var(--color-success)';
}

saveBtn.addEventListener('click', async () => {
  const title = rideTitleInput.value.trim();
  if (!title) { setSaveStatus('Please enter a title.', true); return; }

  saveBtn.disabled = true;
  const original = saveBtn.textContent;
  saveBtn.textContent = 'Saving…';
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setSaveStatus('Please log in first.', true); return; }

    const gpxString = buildTrackGPX(recordedPoints, title);
    const blob = new Blob([gpxString], { type: 'application/gpx+xml' });
    const filePath = `${user.id}/${Date.now()}.gpx`;
    const { data: uploadData, error: uploadErr } = await supabase.storage.from('gpx-files').upload(filePath, blob);
    if (uploadErr) throw uploadErr;

    const durationMin = (recordedPoints.at(-1).time - recordedPoints[0].time) / 60000;
    const elevationM = recordedPoints.reduce((sum, p, i) =>
      i > 0 && p.ele > recordedPoints[i - 1].ele ? sum + (p.ele - recordedPoints[i - 1].ele) : sum, 0);

    const { data: insertData, error: insertErr } = await supabase
      .from('ride_logs')
      .insert({
        title,
        user_id: user.id,
        distance_km: totalDistanceM / 1000,
        duration_min: durationMin,
        elevation_m: elevationM,
        ride_date: recordedPoints[0].time.toISOString(),
        gpx_path: uploadData.path,
        planned_route_id: plannedRoute ? plannedRoute.id : null
      })
      .select('id')
      .single();

    if (insertErr) {
      try { await supabase.storage.from('gpx-files').remove([uploadData.path]); } catch (_) {}
      throw insertErr;
    }

    setSaveStatus('Ride saved!', false);
    window.location.href = `index.html?ride=${insertData.id}`;
  } catch (e) {
    setSaveStatus('Save failed: ' + (e.message || e), true);
    saveBtn.disabled = false;
    saveBtn.textContent = original;
  }
});

// ---------- Leave the page cleanly ----------
window.addEventListener('beforeunload', (e) => {
  if (recording) {
    e.preventDefault();
    e.returnValue = '';
  }
});

// ---------- PWA: register the service worker ----------
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(err => console.warn('SW registration failed:', err));
  });
}
