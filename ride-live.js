// ===============================
// Memory Lanes Ride Journal - ride-live.js
// Record a ride live: GPS track, distance/speed/elapsed telemetry,
// pause/resume, then save it as a ride log. With a ?route= param, it
// also follows a planned route (position vs. the plan). Without one,
// it's a plain "start riding now" recorder - plan later, or not at all.
// ===============================

import supabase from './supabaseClient.js';
// NOTE: this import URL must match the icons.js?v=N script tag in
// ride-live.html exactly. A bare './icons.js' is a DIFFERENT module URL to
// './icons.js?v=N', so the browser loads icons.js twice and applyIcons()
// runs twice, duplicating every button icon on this page.
import { mlIconSVG } from './icons.js?v=75';

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
const broadcastRow     = document.getElementById('live-broadcast-row');
const broadcastToggle  = document.getElementById('live-broadcast-toggle');
const momentBtn        = document.getElementById('live-moment-btn');
const momentForm        = document.getElementById('live-moment-form');
const momentTitleInput  = document.getElementById('live-moment-title');
const momentNoteInput   = document.getElementById('live-moment-note');
const momentSaveBtn     = document.getElementById('live-moment-save-btn');
const momentCancelBtn   = document.getElementById('live-moment-cancel-btn');
const momentsListEl     = document.getElementById('live-moments-list');

// ---------- Utilities ----------
function escapeGpx(str) {
  return String(str).replace(/[<>&"]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
}
function escapeHtml(str) {
  return String(str || '').replace(/[<>&"]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
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
let hasCenteredOnFix = false; // so the very first GPS fix zooms in, not just pans
let liveMoments = [];    // journal entries added mid-ride, saved with the ride on Finish
let momentMarkers = [];  // map pins for liveMoments, kept in the same order
let pendingMoment = null; // captured point waiting on the title/note form
let currentUser = null;      // set once at init; needed for live-position upserts
let lastBroadcastAt = 0;     // throttle: at most one live_positions write per 15s
let groupRide = null;        // { id, token, title } when riding as part of a group ride
let groupRiderMarkers = [];  // other group riders shown on the live map
let groupPollTimer = null;

// ---------- Init ----------
(async () => {
  const params = new URLSearchParams(window.location.search);
  const routeId = params.get('route');
  const groupToken = params.get('group');

  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    loadingEl.textContent = 'Please log in to record a ride.';
    return;
  }

  currentUser = user;

  if (groupToken) {
    // Group ride: the token both admits us (membership row) and returns the
    // route to follow - the route belongs to the host, not to this rider.
    let gr = null;
    try {
      const { data, error } = await supabase.rpc('join_group_ride', { token: groupToken });
      if (error) throw error;
      gr = data;
    } catch (_) {}
    if (!gr || !Array.isArray(gr.route) || gr.route.length < 2) {
      loadingEl.textContent = 'Could not join that group ride. It may have ended. Ask the host for a fresh link.';
      return;
    }
    groupRide = { id: gr.id, token: groupToken, title: gr.title };
    plannedRoute = { id: gr.route_id, title: gr.route_title, route: gr.route, is_public: false };
    plannedRouteSample = sampleArr(gr.route, 150);
    liveTitleEl.textContent = 'Group Ride';
    routeTitleEl.textContent = `Riding "${gr.title}" with the group. Other riders appear on your map as they broadcast.`;
    // Joining a group ride is itself the opt-in: mutual visibility is the
    // point, so the toggle starts ON here (and stays one tap from off).
    broadcastRow.style.display = '';
    broadcastToggle.checked = true;
    startGroupRiderPolling();
  } else if (routeId) {
    const { data: route, error } = await supabase
      .from('planned_routes')
      .select('id, title, route, is_public')
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
    // Live broadcast only makes sense on a shared route - visibility is
    // gated on the invite token, so an unshared route has no possible viewers.
    if (route.is_public) broadcastRow.style.display = '';
  } else {
    liveTitleEl.textContent = 'Record a Ride';
    routeTitleEl.textContent = "Recording a free ride, no plan needed. You can edit or crop the track afterwards from Logs.";
    onRouteCard.style.display = 'none';
  }

  loadingEl.style.display = 'none';
  bodyEl.style.display = '';

  initMap();
})();

// ---------- Other group riders on the live map ----------
async function refreshGroupRiders() {
  if (!groupRide || !map) return;
  let riders = [];
  try {
    const { data, error } = await supabase.rpc('get_group_live_riders', { token: groupRide.token });
    if (error) throw error;
    riders = Array.isArray(data) ? data : []; // server already excludes this rider's own row
  } catch (_) {
    return; // transient failure - keep previous markers, retry next tick
  }
  groupRiderMarkers.forEach(m => map.removeLayer(m));
  groupRiderMarkers = riders.map(r => {
    const marker = L.circleMarker([r.lat, r.lng], {
      radius: 9, color: '#ffd166', weight: 3, fillColor: '#ffd166', fillOpacity: 0.85
    }).addTo(map);
    const speed = r.speed_kmh != null ? ` · ${Math.round(r.speed_kmh)} km/h` : '';
    marker.bindTooltip(`${r.name}${speed}`, { permanent: true, direction: 'top', offset: [0, -10], className: 'live-rider-label' });
    return marker;
  });
}

function startGroupRiderPolling() {
  setTimeout(refreshGroupRiders, 2000); // map exists by then (initMap runs right after init)
  groupPollTimer = setInterval(refreshGroupRiders, 15000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      clearInterval(groupPollTimer);
      groupPollTimer = null;
    } else if (groupRide && !groupPollTimer) {
      refreshGroupRiders();
      groupPollTimer = setInterval(refreshGroupRiders, 15000);
    }
  });
}

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
  stopBroadcasting();
  window.location.href = plannedRoute ? 'planner.html' : 'dashboard.html';
});

// ---------- Moments: journal entries added mid-ride ----------
momentBtn.addEventListener('click', () => {
  if (!recordedPoints.length) {
    alert("Still waiting for a GPS fix. Try again once your position is being tracked.");
    return;
  }
  const pt = recordedPoints[recordedPoints.length - 1];
  pendingMoment = {
    idx: recordedPoints.length - 1,
    lat: pt.lat,
    lng: pt.lng,
    speed: pt.speedKmh || 0,
    elevation: pt.ele || 0,
    title: '',
    note: ''
  };
  momentTitleInput.value = '';
  momentNoteInput.value = '';
  momentForm.style.display = '';
  momentTitleInput.focus();
});

momentSaveBtn.addEventListener('click', () => {
  if (!pendingMoment) return;
  pendingMoment.title = momentTitleInput.value.trim();
  pendingMoment.note = momentNoteInput.value.trim();
  liveMoments.push(pendingMoment);
  addMomentMarker(pendingMoment);
  renderLiveMoments();
  pendingMoment = null;
  momentForm.style.display = 'none';
});

momentCancelBtn.addEventListener('click', () => {
  pendingMoment = null;
  momentForm.style.display = 'none';
});

function addMomentMarker(m) {
  const marker = L.marker([m.lat, m.lng], {
    icon: L.divIcon({
      className: 'moment-pin',
      html: `<span style="color:#8338ec;">${mlIconSVG('pin')}</span>`
    })
  }).addTo(map);
  momentMarkers.push(marker);
}

function renderLiveMoments() {
  if (!liveMoments.length) { momentsListEl.innerHTML = ''; return; }
  momentsListEl.innerHTML = liveMoments.map((m, i) => `
    <div class="moment-entry">
      <div style="display:flex; gap:1rem; align-items:center;">
        <span class="moment-pin-icon">${mlIconSVG('pin')}</span>
        <span>
          <strong>${m.title ? escapeHtml(m.title) : 'Moment ' + (i + 1)}</strong><br>
          ${m.note ? escapeHtml(m.note) : '<em>No note yet</em>'}
        </span>
        <button class="btn-muted delete-live-moment-btn" data-idx="${i}" style="margin-left:auto;color:#ff6b6b;">${mlIconSVG('trash')}</button>
      </div>
    </div>
  `).join('');
  momentsListEl.querySelectorAll('.delete-live-moment-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const idx = +btn.dataset.idx;
      if (momentMarkers[idx]) { map.removeLayer(momentMarkers[idx]); momentMarkers.splice(idx, 1); }
      liveMoments.splice(idx, 1);
      renderLiveMoments();
    });
  });
}

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
  hasCenteredOnFix = false;
  clearLiveMoments();
  beginWatch();

  startBtn.style.display = 'none';
  pauseBtn.style.display = '';
  pauseBtn.textContent = 'Pause';
  momentBtn.style.display = '';
  finishBtn.style.display = '';
}

function clearLiveMoments() {
  momentMarkers.forEach(m => map.removeLayer(m));
  momentMarkers = [];
  liveMoments = [];
  pendingMoment = null;
  momentForm.style.display = 'none';
  renderLiveMoments();
}

function togglePause() {
  if (watching) {
    endWatch();
    pauseBtn.textContent = 'Resume';
    statusBanner.textContent = 'Paused. Distance and time stop counting until you resume.';
  } else {
    beginWatch();
    pauseBtn.textContent = 'Pause';
  }
}

// Set once per beginWatch() call, so the "still waiting" check only fires
// if THIS watch session hasn't produced a fix yet (not stale from before a pause).
let pointsAtWatchStart = 0;
let firstFixTimer = null;

function beginWatch() {
  pointsAtWatchStart = recordedPoints.length;
  statusBanner.textContent = 'Waiting for a GPS signal…';
  clearTimeout(firstFixTimer);
  firstFixTimer = setTimeout(() => {
    if (watching && recordedPoints.length === pointsAtWatchStart) {
      statusBanner.textContent = "Still no GPS fix. Check this site has location permission (and location services are turned on). This feature needs a real GPS signal, so it works best on a phone, not a desktop browser.";
    }
  }, 8000);

  watchId = navigator.geolocation.watchPosition(onPosition, onPositionError, {
    enableHighAccuracy: true, maximumAge: 2000, timeout: 15000
  });
  watching = true;
  requestWakeLock();
}

function endWatch() {
  clearTimeout(firstFixTimer);
  if (watchId != null) navigator.geolocation.clearWatch(watchId);
  watchId = null;
  watching = false;
  releaseWakeLock();
}

function onPosition(pos) {
  if (recordedPoints.length === pointsAtWatchStart) {
    clearTimeout(firstFixTimer);
    statusBanner.textContent = 'Recording your ride…';
  }

  const { latitude, longitude, altitude, speed } = pos.coords;
  const speedKmh = speed != null && Number.isFinite(speed) ? speed * 3.6 : 0;
  const pt = { lat: latitude, lng: longitude, ele: altitude || 0, time: new Date(pos.timestamp), speedKmh };

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
  maybeBroadcastPosition(pt);

  if (followMode) {
    if (!hasCenteredOnFix) {
      // First fix of the ride: zoom in to street level, not just pan at
      // whatever zoom the map happened to be at (which can still be the
      // world view if the initial low-accuracy centering attempt missed).
      map.setView([pt.lat, pt.lng], 16);
      hasCenteredOnFix = true;
    } else {
      map.panTo([pt.lat, pt.lng]);
    }
  }

  updateTelemetry(pt, speed);
}

function onPositionError(err) {
  clearTimeout(firstFixTimer);
  switch (err.code) {
    case err.PERMISSION_DENIED:
      statusBanner.textContent = "Location permission was denied. Allow location access for this site in your browser's settings, then reload and try again.";
      break;
    case err.POSITION_UNAVAILABLE:
      statusBanner.textContent = "Your device can't determine its location right now. Check that location services are turned on.";
      break;
    case err.TIMEOUT:
      statusBanner.textContent = 'Still waiting for a GPS fix. This can take longer with a weak signal or indoors.';
      break;
    default:
      statusBanner.textContent = `Location error: ${err.message}. Check location permissions and try again.`;
  }
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
  stopBroadcasting();
  if (recordedPoints.length < 2) {
    statusBanner.textContent = 'Not enough GPS points were recorded to save this ride.';
    startBtn.style.display = '';
    pauseBtn.style.display = 'none';
    momentBtn.style.display = 'none';
    finishBtn.style.display = 'none';
    clearLiveMoments();
    return;
  }
  pauseBtn.style.display = 'none';
  momentBtn.style.display = 'none';
  momentForm.style.display = 'none';
  pendingMoment = null;
  finishBtn.style.display = 'none';
  recenterBtn.style.display = 'none';
  statusBanner.textContent = 'Ride recorded. Save it below to keep it.';
  saveForm.style.display = '';
  rideTitleInput.value = plannedRoute
    ? `${plannedRoute.title} - ${new Date().toLocaleDateString()}`
    : `Ride - ${new Date().toLocaleDateString()}`;
}

// ---------- Live broadcast (opt-in; visible only via the route's invite link) ----------
function maybeBroadcastPosition(pt) {
  if (!plannedRoute || !currentUser) return;
  if (!plannedRoute.is_public && !groupRide) return; // no possible viewers otherwise
  if (!broadcastToggle || !broadcastToggle.checked || !recording) return;
  const now = Date.now();
  if (now - lastBroadcastAt < 15000) return; // one write per 15s is plenty for a map marker
  lastBroadcastAt = now;
  supabase.from('live_positions').upsert({
    user_id: currentUser.id,
    route_id: plannedRoute.id,
    group_ride_id: groupRide ? groupRide.id : null,
    lat: pt.lat,
    lng: pt.lng,
    speed_kmh: pt.speedKmh || null,
    updated_at: new Date().toISOString()
  }).then(({ error }) => {
    if (error) console.warn('Live position update failed:', error.message);
  });
}

// Best-effort removal; even if it never runs (crash, dead battery), viewers
// stop seeing the rider anyway once the 5-minute freshness window lapses.
function stopBroadcasting() {
  lastBroadcastAt = 0;
  if (!currentUser) return;
  supabase.from('live_positions').delete().eq('user_id', currentUser.id).then(() => {});
}

if (broadcastToggle) {
  broadcastToggle.addEventListener('change', () => {
    if (!broadcastToggle.checked) stopBroadcasting();
    else lastBroadcastAt = 0; // broadcast on the very next GPS fix
  });
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
        planned_route_id: plannedRoute ? plannedRoute.id : null,
        moments: liveMoments
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
