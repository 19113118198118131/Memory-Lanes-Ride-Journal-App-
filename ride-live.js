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
import { mlIconSVG } from './icons.js?v=91';

// Native iOS recorder bridge (Capacitor). Loaded LAZILY: the bridge pulls in
// @capacitor/core from a CDN, so importing it statically would make every web
// page load depend on that CDN (and a failed resolve would break the whole
// module). We only import it when actually running inside the iOS app, where
// recording routes through CoreLocation and keeps tracking with the screen off.
let nativeBridge = null;
async function loadNativeBridge() {
  if (!nativeBridge) nativeBridge = await import('./iosRideRecorder.js?v=90');
  return nativeBridge;
}

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
const elevationEl     = document.getElementById('live-elevation');
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
let elevationGainM = 0;
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
// True only inside the iOS app. Detected WITHOUT importing the bridge, so the
// web never touches the Capacitor CDN dependency.
const nativeMode = !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform());
let nativeSyncTimer = null;   // drains the native buffer while foreground
let nativeErrorListener = null;
let nativeProcessed = 0;      // how many native buffer points are already merged this segment
let groupRide = null;        // { id, token, title } when riding as part of a group ride
let groupRiderMarkers = [];  // other group riders shown on the live map
let groupPollTimer = null;

function setRideState(state) {
  document.body.dataset.rideState = state;
}
setRideState('idle');

// ---------- Crash-safe draft persistence ----------
// The in-progress ride is written to storage as it records, so an iOS app
// eviction, a browser tab reclaim, a crash, or a dead battery can no longer
// silently lose the whole ride. On the next visit we detect the draft and
// offer to recover and save it. In the native app this pairs with the
// recorder plugin's own on-disk buffer (readNativeInterruptedDraft), which
// additionally survives a background process-kill mid-ride.
const DRAFT_KEY = 'ml-live-ride-draft';
let lastDraftWrite = 0;

function persistDraft() {
  if (!recording || recordedPoints.length < 1) return;
  try {
    const payload = {
      v: 1,
      startedAt: startTime ? startTime.getTime() : Date.now(),
      routeId: plannedRoute ? plannedRoute.id : null,
      routeTitle: plannedRoute ? plannedRoute.title : null,
      groupRideId: groupRide ? groupRide.id : null,
      dist: totalDistanceM,
      elev: elevationGainM,
      moments: liveMoments,
      // Compact tuple per point: [lat, lng, ele, timeMs, speedKmh]
      pts: recordedPoints.map(p => [p.lat, p.lng, p.ele, p.time.getTime(), p.speedKmh]),
      savedAt: Date.now()
    };
    localStorage.setItem(DRAFT_KEY, JSON.stringify(payload));
    lastDraftWrite = Date.now();
  } catch (_) {
    // Storage full or disabled: recording keeps working, we just can't checkpoint.
  }
}

// Called on every GPS fix; the actual write is at most once every few seconds
// so a long ride doesn't thrash localStorage.
function persistDraftThrottled() {
  if (Date.now() - lastDraftWrite < 4000) return;
  persistDraft();
}

function clearDraft() {
  try { localStorage.removeItem(DRAFT_KEY); } catch (_) {}
}

function readDraft() {
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    if (!raw) return null;
    const d = JSON.parse(raw);
    if (!d || !Array.isArray(d.pts) || d.pts.length < 2) return null;
    return d;
  } catch (_) { return null; }
}

// Native only: read the disk-persisted CoreLocation buffer left behind when the
// app was killed mid-ride, and shape it like a draft. Returns null unless the
// native layer flags the buffer as interrupted (so a cleanly-finished ride
// isn't re-offered).
async function readNativeInterruptedDraft() {
  try {
    const b = await loadNativeBridge();
    const status = await b.getNativeRideRecordingStatus();
    if (!status || status.recording || !status.interrupted) return null;
    const track = await b.getNativeRideTrack();
    const pts = Array.isArray(track && track.points) ? track.points : [];
    const tuples = [];
    let dist = 0, elev = 0, prev = null;
    for (const p of pts) {
      const lat = Number(p.lat), lng = Number(p.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      const ele = Number.isFinite(Number(p.altitude)) ? Number(p.altitude) : 0;
      const tMs = p.timestamp ? Date.parse(p.timestamp) : Date.now();
      const speedKmh = Number.isFinite(Number(p.speed)) ? Number(p.speed) * 3.6 : 0;
      if (prev) {
        dist += haversineMeters(prev[0], prev[1], lat, lng);
        if (ele > prev[2]) elev += ele - prev[2];
      }
      const tuple = [lat, lng, ele, tMs, speedKmh];
      tuples.push(tuple);
      prev = tuple;
    }
    if (tuples.length < 2) return null;
    return {
      v: 1,
      startedAt: track.startedAt ? Date.parse(track.startedAt) : tuples[0][3],
      routeId: null, routeTitle: null, groupRideId: null,
      dist, elev, moments: [], pts: tuples, savedAt: Date.now(), _native: true
    };
  } catch (_) { return null; }
}

// Drop the native disk buffer too, so a recovered ride isn't offered again.
function clearNativeDraft() {
  if (nativeMode) loadNativeBridge().then(b => b.clearNativeRideTrack()).catch(() => {});
}

// Show a recovery card summarising the interrupted ride, with Save / Discard.
function presentRecovery(draft) {
  let distKm = 0;
  for (let i = 1; i < draft.pts.length; i++) {
    distKm += haversineMeters(draft.pts[i - 1][0], draft.pts[i - 1][1], draft.pts[i][0], draft.pts[i][1]);
  }
  distKm = (distKm / 1000).toFixed(1);
  const started = new Date(draft.startedAt);
  const when = started.toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });

  const overlay = document.createElement('div');
  overlay.className = 'live-recovery-overlay';
  overlay.innerHTML = `
    <div class="live-recovery-card" role="dialog" aria-modal="true" aria-labelledby="live-recovery-title">
      <h2 id="live-recovery-title">Unsaved ride found</h2>
      <p>A ride you were recording didn't get saved — it looks like the app was closed mid-ride.</p>
      <div class="live-recovery-stats">
        <div><span>${distKm}</span><small>km tracked</small></div>
        <div><span>${draft.pts.length}</span><small>GPS points</small></div>
      </div>
      <p class="live-recovery-when">Started ${escapeHtml(when)}</p>
      <div class="live-recovery-actions">
        <button type="button" id="live-recovery-save" class="btn-primary">Recover &amp; Save</button>
        <button type="button" id="live-recovery-discard" class="btn-plain-danger">Discard</button>
      </div>
    </div>`;
  document.body.appendChild(overlay);

  overlay.querySelector('#live-recovery-save').addEventListener('click', () => {
    overlay.remove();
    recoverDraft(draft);
  });
  overlay.querySelector('#live-recovery-discard').addEventListener('click', () => {
    if (!confirm('Permanently discard this unsaved ride?')) return;
    clearDraft();
    clearNativeDraft();
    overlay.remove();
    // Reload so the page sets up a normal fresh ride with no draft.
    window.location.reload();
  });
}

// Restore an interrupted ride into the save-ready state so it can be kept.
function recoverDraft(draft) {
  recordedPoints = draft.pts.map(a => ({
    lat: a[0], lng: a[1], ele: a[2], time: new Date(a[3]), speedKmh: a[4]
  }));
  totalDistanceM = draft.dist || 0;
  elevationGainM = draft.elev || 0;
  startTime = new Date(draft.startedAt);
  liveMoments = Array.isArray(draft.moments) ? draft.moments : [];
  // Keep the planned-route link so the saved ride still ties back to the plan,
  // but we don't have the route geometry here, so hide the live on-route metric.
  if (draft.routeId) {
    plannedRoute = { id: draft.routeId, title: draft.routeTitle || 'Route', route: [], is_public: false };
  }
  onRouteCard.style.display = 'none';

  recordedLine = L.polyline(recordedPoints.map(p => [p.lat, p.lng]), {
    color: '#00c6ff', weight: 4, opacity: 0.9
  }).addTo(map);
  try { map.fitBounds(recordedLine.getBounds(), { padding: [40, 40] }); } catch (_) {}
  liveMoments.forEach(addMomentMarker);
  renderLiveMoments();

  const last = recordedPoints[recordedPoints.length - 1];
  updateTelemetry(last, null);

  recording = false;
  setRideState('saving');
  liveTitleEl.textContent = 'Recovered Ride';
  routeTitleEl.textContent = 'This ride was recovered after the app closed mid-record.';
  startBtn.style.display = 'none';
  pauseBtn.style.display = 'none';
  momentBtn.style.display = 'none';
  finishBtn.style.display = 'none';
  recenterBtn.style.display = 'none';
  statusBanner.textContent = 'Recovered your unsaved ride. Save it below to keep it.';
  saveForm.style.display = '';
  rideTitleInput.value = plannedRoute
    ? `${plannedRoute.title} - ${startTime.toLocaleDateString()}`
    : `Ride - ${startTime.toLocaleDateString()}`;
}

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

  // Before setting up a fresh ride, see if a previous one was cut off mid-record
  // (app evicted, crash, battery). If so, offer to recover it instead.
  let draft = readDraft();
  if (nativeMode) {
    // The native recorder persists its buffer to disk, so after a background
    // process-kill it still holds the part of the ride recorded while the screen
    // was off - more complete than the localStorage draft (which only advances
    // while the app is foreground). Prefer it, but keep the JS-only context
    // (pinned moments, planned-route link) the native layer never sees.
    const nativeDraft = await readNativeInterruptedDraft();
    if (nativeDraft) {
      if (draft && nativeDraft.pts.length >= draft.pts.length) {
        nativeDraft.moments = draft.moments;
        nativeDraft.routeId = draft.routeId;
        nativeDraft.routeTitle = draft.routeTitle;
        draft = nativeDraft;
      } else if (!draft) {
        draft = nativeDraft;
      }
    }
  }
  if (draft) {
    loadingEl.style.display = 'none';
    bodyEl.style.display = '';
    initMap();
    presentRecovery(draft);
    return;
  }

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
    const groupPanel = document.getElementById('live-group-panel');
    if (groupPanel) groupPanel.style.display = '';
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

// ---------- Other group riders: markers on the map + the Riding With You panel ----------
function freshnessLabel(updatedAt) {
  const ageS = Math.max(0, (Date.now() - new Date(updatedAt).getTime()) / 1000);
  if (ageS < 45) return 'just now';
  if (ageS < 90) return '1 min ago';
  return `${Math.round(ageS / 60)} min ago`;
}

function renderGroupPanel(riders) {
  const panel = document.getElementById('live-group-list');
  if (!panel) return;
  if (!riders.length) {
    panel.innerHTML = '<p class="chart-desc" style="margin:0;">No one else is broadcasting yet. Riders appear here the moment they start.</p>';
    return;
  }
  const myPos = recordedPoints.length ? recordedPoints[recordedPoints.length - 1] : null;
  panel.innerHTML = riders.map((r, i) => {
    const speed = r.speed_kmh != null ? `${Math.round(r.speed_kmh)} km/h` : 'stopped';
    const away = myPos ? `${(haversineMeters(myPos.lat, myPos.lng, r.lat, r.lng) / 1000).toFixed(1)} km away · ` : '';
    return `
      <button type="button" class="live-group-rider" data-index="${i}">
        <span class="live-group-rider-dot"></span>
        <span class="live-group-rider-name">${escapeHtml(r.name)}</span>
        <span class="live-group-rider-meta">${away}${speed} · ${freshnessLabel(r.updated_at)}</span>
        <span class="live-group-rider-find">Find</span>
      </button>`;
  }).join('');
  panel.querySelectorAll('.live-group-rider').forEach(btn => {
    btn.addEventListener('click', () => {
      const r = riders[parseInt(btn.dataset.index, 10)];
      if (!r || !map) return;
      // Looking at a mate means leaving follow-me; the existing Recenter
      // button is the way back, same as after a manual map drag.
      followMode = false;
      if (recording) recenterBtn.style.display = '';
      map.setView([r.lat, r.lng], Math.max(map.getZoom(), 14));
    });
  });
}

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
  renderGroupPanel(riders);
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
  map = L.map('live-map', { zoomControl: false });
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
  clearDraft(); // deliberate abandon: don't offer to recover this one later
  clearNativeDraft();
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
  persistDraft();
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
      if (recording) persistDraft();
    });
  });
}

function startRide() {
  if (!nativeMode && !navigator.geolocation) {
    alert('Geolocation is not supported on this device or browser.');
    return;
  }
  recordedPoints = [];
  totalDistanceM = 0;
  elevationGainM = 0;
  startTime = new Date();
  recording = true;
  setRideState('recording');
  followMode = true;
  hasCenteredOnFix = false;
  clearLiveMoments();
  if (nativeMode) loadNativeBridge().then(b => b.clearNativeRideTrack()).catch(() => {}); // drop stale buffer from a prior ride
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

async function togglePause() {
  if (watching) {
    if (nativeMode) await drainNative(); // capture points up to the pause before stopping
    endWatch();
    persistDraft(); // checkpoint the full track at the pause boundary
    pauseBtn.textContent = 'Resume';
    statusBanner.textContent = 'Paused. Distance and time stop counting until you resume.';
    setRideState('paused');
  } else {
    beginWatch();
    pauseBtn.textContent = 'Pause';
    setRideState('recording');
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
      statusBanner.textContent = nativeMode
        ? "Still no GPS fix. Open Settings and allow Location 'Always' for Memory Lanes so it can keep tracking with the screen off."
        : "Still no GPS fix. Check this site has location permission (and location services are turned on). This feature needs a real GPS signal, so it works best on a phone, not a desktop browser.";
    }
  }, 8000);

  if (nativeMode) { beginNativeWatch(); return; }

  watchId = navigator.geolocation.watchPosition(onPosition, onPositionError, {
    enableHighAccuracy: true, maximumAge: 2000, timeout: 15000
  });
  watching = true;
  requestWakeLock();
}

function endWatch() {
  clearTimeout(firstFixTimer);
  if (nativeMode) { endNativeWatch(); return; }
  if (watchId != null) navigator.geolocation.clearWatch(watchId);
  watchId = null;
  watching = false;
  releaseWakeLock();
}

// ---------- Native (iOS) position source ----------
// CoreLocation records continuously, buffering points even while the app is
// backgrounded and JS is suspended. We drain that authoritative buffer on a
// timer (foreground) and on resume/finish, replaying each new point through
// the same onPosition() pipeline the web path uses.
async function beginNativeWatch() {
  nativeProcessed = 0; // native start() wipes its buffer, so this segment starts fresh
  watching = true;
  try {
    const b = await loadNativeBridge();
    await b.requestRideRecorderPermission();
    await b.startNativeRideRecording();
    if (!nativeErrorListener) {
      nativeErrorListener = await b.onNativeRideError(err => {
        if (err && err.message) statusBanner.textContent = `Location error: ${err.message}`;
      });
    }
  } catch (e) {
    watching = false;
    clearTimeout(firstFixTimer);
    statusBanner.textContent = "Couldn't start GPS. Allow Location 'Always' for Memory Lanes in Settings, then try again.";
    // Roll the controls back to the pre-start state so the rider can retry.
    startBtn.style.display = '';
    pauseBtn.style.display = 'none';
    momentBtn.style.display = 'none';
    finishBtn.style.display = 'none';
    recording = false;
    setRideState('idle');
    return;
  }
  clearInterval(nativeSyncTimer);
  nativeSyncTimer = setInterval(drainNative, 2000);
  drainNative();
}

function endNativeWatch() {
  watching = false;
  clearInterval(nativeSyncTimer);
  nativeSyncTimer = null;
  if (nativeBridge) nativeBridge.stopNativeRideRecording().catch(() => {});
}

async function drainNative() {
  let pts;
  try {
    const b = await loadNativeBridge();
    const track = await b.getNativeRideTrack();
    pts = Array.isArray(track && track.points) ? track.points : [];
  } catch (_) { return; }
  for (let i = nativeProcessed; i < pts.length; i++) {
    const np = pts[i];
    if (!Number.isFinite(np.lat) || !Number.isFinite(np.lng)) continue;
    onPosition({
      coords: { latitude: np.lat, longitude: np.lng, altitude: np.altitude, speed: np.speed },
      timestamp: np.timestamp ? Date.parse(np.timestamp) : Date.now()
    });
  }
  nativeProcessed = pts.length;
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
    if (Number.isFinite(pt.ele) && Number.isFinite(prev.ele) && pt.ele > prev.ele) {
      elevationGainM += pt.ele - prev.ele;
    }
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
  persistDraftThrottled();
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

  const elapsedSec = Math.max(0, Math.floor((pt.time - startTime) / 1000));
  const hours = Math.floor(elapsedSec / 3600);
  const mins = Math.floor((elapsedSec % 3600) / 60);
  const secs = elapsedSec % 60;
  elapsedEl.textContent = hours
    ? `${hours}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`
    : `${mins}:${String(secs).padStart(2, '0')}`;

  const kmh = speedMs != null && Number.isFinite(speedMs) ? speedMs * 3.6 : null;
  speedEl.textContent = kmh != null ? `${kmh.toFixed(0)} km/h` : '–';
  if (elevationEl) elevationEl.textContent = `${Math.round(elevationGainM)} m`;

  if (!plannedRoute || !plannedRouteSample) return;
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

async function finishRide() {
  // Pull in any points buffered while backgrounded before we stop and judge
  // whether there's enough to save.
  if (nativeMode && watching) await drainNative();
  endWatch();
  recording = false;
  setRideState('saving');
  stopBroadcasting();
  if (recordedPoints.length < 2) {
    statusBanner.textContent = 'Not enough GPS points were recorded to save this ride.';
    startBtn.style.display = '';
    pauseBtn.style.display = 'none';
    momentBtn.style.display = 'none';
    finishBtn.style.display = 'none';
    setRideState('idle');
    clearLiveMoments();
    clearDraft(); // nothing worth recovering
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
  if (document.visibilityState !== 'visible' || !watching) return;
  requestWakeLock();
  // Coming back to the foreground: pull in everything CoreLocation buffered
  // while JS was suspended, so the on-screen track catches up instantly.
  if (nativeMode) drainNative();
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

    clearDraft(); // the ride is safely in the database now
    clearNativeDraft();
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
