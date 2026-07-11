// ===============================
// Memory Lanes Ride Journal - planner.js
// Plan a route on the map (click to add waypoints, snapped to real roads
// via OSRM), preview distance/elevation, then save it or export a GPX.
// ===============================

import supabase from './supabaseClient.js';
import { mlIconSVG } from './icons.js?v=66';

// ---------- DOM references ----------
const authNote         = document.getElementById('planner-auth-note');
const plannerBody      = document.getElementById('planner-body');
const mapSection       = document.getElementById('planner-map-section');
const mapHint          = document.getElementById('planner-map-hint');
const distanceEl       = document.getElementById('planner-distance');
const elevationEl      = document.getElementById('planner-elevation');
const waypointCountEl  = document.getElementById('planner-waypoint-count');
const waypointListEl   = document.getElementById('planner-waypoint-list');
const undoBtn          = document.getElementById('planner-undo-btn');
const redoBtn          = document.getElementById('planner-redo-btn');
const reverseBtn       = document.getElementById('planner-reverse-btn');
const connectStartBtn  = document.getElementById('planner-connect-start-btn');
const cropBtn          = document.getElementById('planner-crop-btn');
const splitBtn         = document.getElementById('planner-split-btn');
const clearBtn         = document.getElementById('planner-clear-btn');
const routeTitleInput  = document.getElementById('planner-route-title');
const saveBtn          = document.getElementById('planner-save-btn');
const exportBtn        = document.getElementById('planner-export-btn');
const saveStatusEl     = document.getElementById('planner-save-status');
const routesListEl     = document.getElementById('planner-routes-list');
const searchInput      = document.getElementById('planner-search-input');
const searchBtn        = document.getElementById('planner-search-btn');
const searchResultsEl  = document.getElementById('planner-search-results');
const dashboardBtn     = document.getElementById('planner-dashboard-btn');
const recordBtn        = document.getElementById('planner-record-btn');
const onboardingEl        = document.getElementById('planner-onboarding');
const workspaceEl         = document.getElementById('planner-workspace');
const onboardingContinueBtn = document.getElementById('planner-onboarding-continue');
const onboardingSkipBtn     = document.getElementById('planner-onboarding-skip');
const rideSetupBtn        = document.getElementById('planner-ride-setup-btn');
const goalHintEl          = document.getElementById('planner-goal-hint');

// ---------- Utilities (small, duplicated per-page like the rest of the app) ----------
function escapeHtml(str) {
  return String(str ?? '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
  );
}
function showToast(msg, mode = 'info') {
  const toast = document.createElement('div');
  toast.className = 'custom-toast';
  toast.textContent = msg;
  toast.style.position = 'fixed';
  toast.style.top = '50%';
  toast.style.left = '50%';
  toast.style.transform = 'translate(-50%, -50%)';
  toast.style.background = mode === 'delete' ? '#ff3333' : (mode === 'add' ? '#21c821' : '#333');
  toast.style.color = '#fff';
  toast.style.padding = '0.8em 1.7em';
  toast.style.fontSize = '1.18rem';
  toast.style.borderRadius = '999px';
  toast.style.boxShadow = '0 3px 14px #0004';
  toast.style.zIndex = '99999';
  document.body.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    setTimeout(() => { if (toast.parentNode) toast.parentNode.removeChild(toast); }, 450);
  }, 1200);
}

// ---------- State ----------
let map = null;
let markers = [];
let routeLine = null;
let waypoints = [];          // [{lat, lng}, ...] in the order clicked
let routeCoords = [];        // dense [lat, lng] pairs for the drawn/snapped route
let historyStack = [[]];
let historyIndex = 0;
let recalcTimer = null;
let recalcAbort = null;
let fitOnNextDraw = false;
let currentDistanceKm = null;
let currentElevationM = null;
let savedRoutes = [];
let cropMode = false;
let splitMode = false;
let cropPicks = [];  // up to 2 waypoint indices picked while cropMode is on
let cropMarkers = [];
let startFrom = null;        // 'current' | 'search' | 'map' | null (only set via onboarding)
let routeType = 'one-way';   // 'one-way' | 'return' | 'loop'
let rideGoal = null;         // 'short' | 'half-day' | 'full-day' | null
let onboardingChoices = { start: null, type: null, goal: null };

// ---------- Init ----------
(async () => {
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    authNote.style.display = '';
    plannerBody.style.display = 'none';
    return;
  }
  authNote.style.display = 'none';
  plannerBody.style.display = '';
  initMap();
  updateButtons();
  updateGoalHint();
  await loadSavedRoutes();

  const loadId = new URLSearchParams(window.location.search).get('load');
  const loadRoute = loadId ? savedRoutes.find(r => r.id === loadId) : null;
  if (loadRoute) {
    loadSavedRouteIntoPlanner(loadRoute); // reveals the workspace itself
  } else {
    onboardingEl.style.display = '';
    workspaceEl.style.display = 'none';
  }
})();

if (dashboardBtn) {
  dashboardBtn.addEventListener('click', () => { window.location.href = 'dashboard.html'; });
}
if (recordBtn) {
  recordBtn.addEventListener('click', () => { window.location.href = 'ride-live.html'; });
}

// ---------- Goal-first onboarding ----------
// The map/waypoint mechanics stay exactly as before; this panel just sets
// intent up front (where to start, what shape, how long) so a first-time
// user isn't dropped straight into "click the map and hope."
document.querySelectorAll('.onboarding-option').forEach(btn => {
  btn.addEventListener('click', () => {
    const groupName = btn.closest('.onboarding-group').dataset.group;
    onboardingChoices[groupName] = btn.dataset.value;
    refreshOnboardingButtonStates();
  });
});

function refreshOnboardingButtonStates() {
  document.querySelectorAll('.onboarding-group').forEach(group => {
    const groupName = group.dataset.group;
    group.querySelectorAll('.onboarding-option').forEach(b => {
      b.classList.toggle('active', b.dataset.value === onboardingChoices[groupName]);
    });
  });
  onboardingContinueBtn.disabled = !(onboardingChoices.start && onboardingChoices.type && onboardingChoices.goal);
}

onboardingContinueBtn.addEventListener('click', () => {
  startFrom = onboardingChoices.start;
  routeType = onboardingChoices.type;
  rideGoal = onboardingChoices.goal;
  finishOnboarding();
});
onboardingSkipBtn.addEventListener('click', () => {
  startFrom = null;
  routeType = 'one-way';
  rideGoal = null;
  finishOnboarding();
});
if (rideSetupBtn) {
  rideSetupBtn.addEventListener('click', () => {
    onboardingChoices = { start: startFrom, type: routeType, goal: rideGoal };
    refreshOnboardingButtonStates();
    workspaceEl.style.display = 'none';
    onboardingEl.style.display = '';
  });
}

function finishOnboarding() {
  updateButtons();
  updateGoalHint();
  onboardingEl.style.display = 'none';
  workspaceEl.style.display = '';
  handleStartFrom();
  setTimeout(() => map.invalidateSize(), 50); // map was hidden, Leaflet needs a nudge
}

function handleStartFrom() {
  if (startFrom === 'current') {
    if (!navigator.geolocation) { showToast('Geolocation is not supported on this device.', 'info'); return; }
    showToast('Locating you…', 'info');
    navigator.geolocation.getCurrentPosition(
      pos => {
        map.setView([pos.coords.latitude, pos.coords.longitude], 14);
        addWaypoint({ lat: pos.coords.latitude, lng: pos.coords.longitude });
      },
      () => showToast('Could not get your location. Click the map to start instead.', 'info'),
      { timeout: 8000 }
    );
  } else if (startFrom === 'search') {
    searchInput.focus();
  }
  // 'map' (or skipped): no-op, the existing click-to-add-a-waypoint flow already works
}

// A "Loop" route auto-closes back to its first point, and a "Return" route
// auto-mirrors itself back along the same waypoints — the rider picks the
// shape up front and never needs to know these are separate manual tools.
function getEffectiveWaypoints() {
  if (routeType === 'loop' && waypoints.length >= 2) {
    const first = waypoints[0], last = waypoints[waypoints.length - 1];
    if (first.lat === last.lat && first.lng === last.lng) return waypoints;
    return waypoints.concat([{ lat: first.lat, lng: first.lng }]);
  }
  if (routeType === 'return' && waypoints.length >= 2) {
    return waypoints.concat(waypoints.slice(0, -1).reverse());
  }
  return waypoints;
}

const GOAL_RANGES = {
  'short':    { label: 'Short ride',    min: 0,   max: 50 },
  'half-day': { label: 'Half day ride', min: 50,  max: 180 },
  'full-day': { label: 'Full day ride', min: 180, max: Infinity }
};
function updateGoalHint() {
  if (!goalHintEl) return;
  const g = GOAL_RANGES[rideGoal];
  if (!g) { goalHintEl.style.display = 'none'; return; }
  goalHintEl.style.display = '';
  const rangeText = g.max === Infinity ? `${g.min}+ km` : `${g.min}–${g.max} km`;
  if (currentDistanceKm == null) {
    goalHintEl.textContent = `Goal: ${g.label} · aim for ${rangeText}`;
    goalHintEl.className = 'planner-goal-hint';
  } else if (currentDistanceKm >= g.min && currentDistanceKm <= g.max) {
    goalHintEl.textContent = `On track for a ${g.label.toLowerCase()} (${rangeText})`;
    goalHintEl.className = 'planner-goal-hint planner-goal-hint-ok';
  } else if (currentDistanceKm < g.min) {
    goalHintEl.textContent = `Add more stops to reach your ${g.label.toLowerCase()} goal (${rangeText})`;
    goalHintEl.className = 'planner-goal-hint planner-goal-hint-under';
  } else {
    goalHintEl.textContent = `Longer than a typical ${g.label.toLowerCase()} (${rangeText})`;
    goalHintEl.className = 'planner-goal-hint planner-goal-hint-over';
  }
}

function initMap() {
  map = L.map('planner-map', { zoomControl: true });
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);
  map.setView([20, 0], 2);
  if (navigator.geolocation) {
    navigator.geolocation.getCurrentPosition(
      pos => map.setView([pos.coords.latitude, pos.coords.longitude], 12),
      () => {},
      { timeout: 4000 }
    );
  }
  map.on('click', (e) => {
    if (cropMode || splitMode) return; // these tools require clicking the route line itself
    addWaypoint(e.latlng);
  });
}

// ---------- Waypoint mutation ----------
function addWaypoint(latlng) {
  waypoints.push({ lat: latlng.lat, lng: latlng.lng });
  if (waypoints.length === 2) fitOnNextDraw = true;
  afterWaypointsChanged();
}

function removeWaypoint(index) {
  waypoints.splice(index, 1);
  afterWaypointsChanged();
}

function insertWaypointFromClick(latlng) {
  if (waypoints.length < 2) { addWaypoint(latlng); return; }
  const clickPt = map.latLngToLayerPoint(latlng);
  let bestIdx = waypoints.length;
  let bestDist = Infinity;
  for (let i = 0; i < waypoints.length - 1; i++) {
    const p1 = map.latLngToLayerPoint(L.latLng(waypoints[i].lat, waypoints[i].lng));
    const p2 = map.latLngToLayerPoint(L.latLng(waypoints[i + 1].lat, waypoints[i + 1].lng));
    const d = pointToSegmentDistance(clickPt, p1, p2);
    if (d < bestDist) { bestDist = d; bestIdx = i + 1; }
  }
  waypoints.splice(bestIdx, 0, { lat: latlng.lat, lng: latlng.lng });
  afterWaypointsChanged();
}

function pointToSegmentDistance(p, v, w) {
  const l2 = v.distanceTo(w) ** 2;
  if (l2 === 0) return p.distanceTo(v);
  let t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2;
  t = Math.max(0, Math.min(1, t));
  return p.distanceTo(L.point(v.x + t * (w.x - v.x), v.y + t * (w.y - v.y)));
}

function afterWaypointsChanged(recordHistory = true) {
  // Any waypoint mutation invalidates an in-progress crop/split pick
  if (cropMode) setCropMode(false);
  if (splitMode) setSplitMode(false);
  if (recordHistory) pushHistory();
  rebuildMarkers();
  renderWaypointList();
  mapHint.style.display = waypoints.length ? 'none' : '';
  waypointCountEl.textContent = String(waypoints.length);
  updateButtons();
  scheduleRecalc();
}

// ---------- Undo/redo ----------
function pushHistory() {
  const snapshot = waypoints.map(w => ({ ...w }));
  historyStack = historyStack.slice(0, historyIndex + 1);
  historyStack.push(snapshot);
  historyIndex++;
}
function undo() {
  if (historyIndex <= 0) return;
  if (cropMode) setCropMode(false);
  if (splitMode) setSplitMode(false);
  historyIndex--;
  waypoints = historyStack[historyIndex].map(w => ({ ...w }));
  rebuildMarkers();
  renderWaypointList();
  mapHint.style.display = waypoints.length ? 'none' : '';
  waypointCountEl.textContent = String(waypoints.length);
  updateButtons();
  scheduleRecalc();
}
function redo() {
  if (historyIndex >= historyStack.length - 1) return;
  if (cropMode) setCropMode(false);
  if (splitMode) setSplitMode(false);
  historyIndex++;
  waypoints = historyStack[historyIndex].map(w => ({ ...w }));
  rebuildMarkers();
  renderWaypointList();
  mapHint.style.display = waypoints.length ? 'none' : '';
  waypointCountEl.textContent = String(waypoints.length);
  updateButtons();
  scheduleRecalc();
}
undoBtn.addEventListener('click', undo);
redoBtn.addEventListener('click', redo);

clearBtn.addEventListener('click', () => {
  if (!waypoints.length) return;
  if (!confirm('Clear the current route?')) return;
  waypoints = [];
  setCropMode(false);
  setSplitMode(false);
  afterWaypointsChanged();
});

function updateButtons() {
  undoBtn.disabled = historyIndex <= 0;
  redoBtn.disabled = historyIndex >= historyStack.length - 1;
  clearBtn.disabled = waypoints.length === 0;
  const enoughPoints = waypoints.length >= 2;
  saveBtn.disabled = !enoughPoints;
  exportBtn.disabled = !enoughPoints;
  reverseBtn.disabled = !enoughPoints;
  // A "Loop" route closes itself automatically (see getEffectiveWaypoints),
  // so the manual button would just be a confusing, redundant no-op.
  connectStartBtn.style.display = routeType === 'loop' ? 'none' : '';
  connectStartBtn.disabled = !enoughPoints;
  cropBtn.disabled = !enoughPoints;
  splitBtn.disabled = !enoughPoints;
}

// ---------- Reverse / Connect to Start ----------
reverseBtn.addEventListener('click', () => {
  if (waypoints.length < 2) return;
  waypoints = waypoints.slice().reverse();
  afterWaypointsChanged();
  showToast('Route direction reversed.', 'add');
});

connectStartBtn.addEventListener('click', () => {
  if (waypoints.length < 2) return;
  const first = waypoints[0], last = waypoints[waypoints.length - 1];
  if (first.lat === last.lat && first.lng === last.lng) {
    showToast('Route already returns to the start.', 'info');
    return;
  }
  waypoints = waypoints.concat([{ lat: first.lat, lng: first.lng }]);
  afterWaypointsChanged();
  showToast('Return leg added — route now ends where it started.', 'add');
});

// ---------- Crop: click the route twice to keep only what's between ----------
function setCropMode(on) {
  if (on) {
    if (waypoints.length < 2) return;
    setSplitMode(false);
    showToast('Crop: click the route to keep from, then click again to keep until.', 'info');
  }
  cropMode = on;
  clearCropMarkers();
  cropBtn.classList.toggle('active', on);
}
function clearCropMarkers() {
  cropMarkers.forEach(m => map.removeLayer(m));
  cropMarkers = [];
  cropPicks = [];
}
function nearestWaypointIndex(latlng) {
  let bestIdx = 0, bestDist = Infinity;
  waypoints.forEach((w, i) => {
    const d = L.latLng(w.lat, w.lng).distanceTo(latlng);
    if (d < bestDist) { bestDist = d; bestIdx = i; }
  });
  return bestIdx;
}
function handleCropClick(latlng) {
  const idx = nearestWaypointIndex(latlng);
  cropPicks.push(idx);
  const marker = L.circleMarker([waypoints[idx].lat, waypoints[idx].lng], {
    radius: 7, color: '#fff', weight: 2, fillColor: '#ff3333', fillOpacity: 1
  }).addTo(map);
  cropMarkers.push(marker);
  if (cropPicks.length < 2) return;

  let [a, b] = cropPicks;
  if (a > b) [a, b] = [b, a];
  if (a === b) {
    showToast('Pick two different points.', 'info');
    clearCropMarkers();
    return;
  }
  const kept = waypoints.slice(a, b + 1);
  if (!confirm(`Keep ${kept.length} of ${waypoints.length} waypoints and discard the rest?`)) {
    setCropMode(false);
    return;
  }
  waypoints = kept;
  setCropMode(false);
  afterWaypointsChanged();
  showToast('Route cropped.', 'add');
}
cropBtn.addEventListener('click', () => setCropMode(!cropMode));

// ---------- Split: click the route once to export it as two GPX files ----------
function setSplitMode(on) {
  if (on) {
    if (waypoints.length < 2) return;
    setCropMode(false);
    showToast('Split: click the route where it should split into two files.', 'info');
  }
  splitMode = on;
  splitBtn.classList.toggle('active', on);
}
function findNearestRouteCoordIndex(latlng) {
  let bestIdx = 0, bestDist = Infinity;
  routeCoords.forEach((c, i) => {
    const d = L.latLng(c[0], c[1]).distanceTo(latlng);
    if (d < bestDist) { bestDist = d; bestIdx = i; }
  });
  return bestIdx;
}
function handleSplitClick(latlng) {
  const idx = findNearestRouteCoordIndex(latlng);
  if (idx < 1 || idx > routeCoords.length - 2) {
    showToast("Pick a point that isn't the very start or end.", 'info');
    return;
  }
  const partA = routeCoords.slice(0, idx + 1);
  const partB = routeCoords.slice(idx);
  const title = routeTitleInput.value.trim() || 'Planned Route';
  if (!confirm(`Split into two GPX files here? Part 1: ${partA.length} points, Part 2: ${partB.length} points.`)) {
    setSplitMode(false);
    return;
  }
  downloadGPX(partA, `${title} (Part 1)`);
  downloadGPX(partB, `${title} (Part 2)`);
  setSplitMode(false);
  showToast('Downloaded both parts.', 'add');
}
splitBtn.addEventListener('click', () => setSplitMode(!splitMode));

// ---------- Markers ----------
function rebuildMarkers() {
  markers.forEach(m => map.removeLayer(m));
  markers = waypoints.map((wp, i) => createMarker(wp, i));
}
function createMarker(wp, i) {
  const label = i === 0 ? 'Start' : (i === waypoints.length - 1 ? 'End' : `Stop ${i}`);
  const marker = L.marker([wp.lat, wp.lng], { draggable: true, title: label }).addTo(map);
  marker.bindPopup(`<div class="planner-popup"><strong>${escapeHtml(label)}</strong><button type="button" class="planner-popup-remove">Remove</button></div>`);
  marker.on('dragend', () => {
    const ll = marker.getLatLng();
    waypoints[i] = { lat: ll.lat, lng: ll.lng };
    afterWaypointsChanged();
  });
  marker.on('popupopen', () => {
    const el = marker.getPopup().getElement();
    const btn = el && el.querySelector('.planner-popup-remove');
    if (btn) btn.onclick = () => removeWaypoint(i);
  });
  marker.on('contextmenu', (e) => {
    e.originalEvent.preventDefault();
    removeWaypoint(i);
  });
  return marker;
}

// ---------- Waypoint list panel ----------
function renderWaypointList() {
  if (!waypoints.length) { waypointListEl.innerHTML = ''; return; }
  waypointListEl.innerHTML = waypoints.map((wp, i) => {
    const label = i === 0 ? 'Start' : (i === waypoints.length - 1 ? 'End' : `Stop ${i}`);
    return `
      <div class="waypoint-item" data-index="${i}">
        <span class="waypoint-label">${escapeHtml(label)}</span>
        <span class="waypoint-coords">${wp.lat.toFixed(4)}, ${wp.lng.toFixed(4)}</span>
        <span class="waypoint-actions">
          <button type="button" class="waypoint-move" data-dir="-1" ${i === 0 ? 'disabled' : ''} aria-label="Move ${escapeHtml(label)} up">&uarr;</button>
          <button type="button" class="waypoint-move" data-dir="1" ${i === waypoints.length - 1 ? 'disabled' : ''} aria-label="Move ${escapeHtml(label)} down">&darr;</button>
          <button type="button" class="waypoint-remove" aria-label="Remove ${escapeHtml(label)}">${mlIconSVG('x')}</button>
        </span>
      </div>`;
  }).join('');
}
waypointListEl.addEventListener('click', (e) => {
  const item = e.target.closest('.waypoint-item');
  if (!item) return;
  const idx = parseInt(item.dataset.index, 10);
  if (e.target.closest('.waypoint-remove')) { removeWaypoint(idx); return; }
  const moveBtn = e.target.closest('.waypoint-move');
  if (moveBtn) {
    const swapWith = idx + parseInt(moveBtn.dataset.dir, 10);
    if (swapWith < 0 || swapWith >= waypoints.length) return;
    [waypoints[idx], waypoints[swapWith]] = [waypoints[swapWith], waypoints[idx]];
    afterWaypointsChanged();
  }
});

// ---------- Routing (OSRM, snapped to roads; falls back to straight lines) ----------
function scheduleRecalc(delay = 400) {
  clearTimeout(recalcTimer);
  recalcTimer = setTimeout(recalcRoute, delay);
}

async function recalcRoute() {
  if (recalcAbort) recalcAbort.abort();

  if (waypoints.length < 2) {
    if (routeLine) { map.removeLayer(routeLine); routeLine = null; }
    routeCoords = [];
    setDistanceText(null);
    setElevationText(null);
    updateGoalHint();
    return;
  }

  recalcAbort = new AbortController();
  const signal = recalcAbort.signal;
  setElevationText('loading');

  const effective = getEffectiveWaypoints();
  let coords, distanceKm, fallback = false;
  try {
    const coordStr = effective.map(w => `${w.lng},${w.lat}`).join(';');
    const url = `https://router.project-osrm.org/route/v1/driving/${coordStr}?overview=full&geometries=geojson`;
    const resp = await fetch(url, { signal });
    if (!resp.ok) throw new Error('routing failed');
    const data = await resp.json();
    if (data.code !== 'Ok' || !data.routes || !data.routes[0]) throw new Error('no route found');
    coords = data.routes[0].geometry.coordinates.map(c => [c[1], c[0]]);
    distanceKm = data.routes[0].distance / 1000;
  } catch (e) {
    if (e.name === 'AbortError') return;
    fallback = true;
    coords = effective.map(w => [w.lat, w.lng]);
    distanceKm = straightLineDistanceKm(effective);
  }

  routeCoords = coords;
  drawRouteLine(coords, fallback, fitOnNextDraw);
  fitOnNextDraw = false;
  setDistanceText(distanceKm);
  updateGoalHint();

  try {
    const gain = await estimateElevationGain(coords, signal);
    setElevationText(gain);
  } catch (e) {
    if (e.name !== 'AbortError') setElevationText(null);
  }
}

function straightLineDistanceKm(pts) {
  let total = 0;
  for (let i = 1; i < pts.length; i++) {
    total += L.latLng(pts[i - 1].lat, pts[i - 1].lng).distanceTo(L.latLng(pts[i].lat, pts[i].lng));
  }
  return total / 1000;
}

function drawRouteLine(coords, fallback, fit) {
  if (routeLine) { map.removeLayer(routeLine); routeLine = null; }
  if (coords.length < 2) return;
  routeLine = L.polyline(coords, {
    color: fallback ? '#ffd166' : '#64ffda',
    weight: 5,
    opacity: 0.85,
    dashArray: fallback ? '8,8' : null
  }).addTo(map);
  routeLine.on('click', (e) => {
    L.DomEvent.stopPropagation(e);
    if (cropMode) { handleCropClick(e.latlng); return; }
    if (splitMode) { handleSplitClick(e.latlng); return; }
    insertWaypointFromClick(e.latlng);
  });
  if (fit) map.fitBounds(routeLine.getBounds(), { padding: [40, 40] });
}

function setDistanceText(km) {
  currentDistanceKm = km;
  distanceEl.textContent = km == null ? '–' : `${km.toFixed(1)} km`;
}
function setElevationText(v) {
  if (v === 'loading') { elevationEl.textContent = '…'; return; }
  currentElevationM = v;
  elevationEl.textContent = v == null ? '–' : `+${v} m`;
}

// ---------- Elevation (Open-Meteo, sampled along the route) ----------
function sampleCoords(coords, maxPoints) {
  if (coords.length <= maxPoints) return coords;
  const step = (coords.length - 1) / (maxPoints - 1);
  const out = [];
  for (let i = 0; i < maxPoints; i++) out.push(coords[Math.round(i * step)]);
  return out;
}
async function estimateElevationGain(coords, signal) {
  if (coords.length < 2) return 0;
  const sampled = sampleCoords(coords, 100);
  const lats = sampled.map(c => c[0].toFixed(5)).join(',');
  const lons = sampled.map(c => c[1].toFixed(5)).join(',');
  const url = `https://api.open-meteo.com/v1/elevation?latitude=${lats}&longitude=${lons}`;
  const resp = await fetch(url, { signal });
  if (!resp.ok) throw new Error('elevation lookup failed');
  const data = await resp.json();
  const elevations = data.elevation || [];
  let gain = 0;
  for (let i = 1; i < elevations.length; i++) {
    const diff = elevations[i] - elevations[i - 1];
    if (diff > 1.5) gain += diff; // ignore small DEM noise
  }
  return Math.round(gain);
}

// ---------- Search (Photon/Komoot geocoding) ----------
// Nominatim's public instance blocks/rate-limits direct browser (client-side)
// geocoding under its usage policy, which is why this used to silently fail.
// Photon is built for exactly this use case: same OSM data, CORS-friendly, no key.
//
// Picking a result doesn't just move the map: it drops a pin and offers an
// action menu (set as start / add as stop / set as destination / just look),
// since "the map moved" is ambiguous about whether the place joined the route.
const NZ_BIAS = { lat: -41.5, lon: 173.0 }; // soft ranking bias, doesn't exclude other results
const RECENT_SEARCHES_KEY = 'ml-recent-searches';
const MAX_RECENT_SEARCHES = 5;
let searchResultMarker = null;

function getRecentSearches() {
  try { return JSON.parse(localStorage.getItem(RECENT_SEARCHES_KEY)) || []; } catch (_) { return []; }
}
function saveRecentSearch(q) {
  if (!q) return;
  let recents = getRecentSearches().filter(r => r.toLowerCase() !== q.toLowerCase());
  recents.unshift(q);
  try { localStorage.setItem(RECENT_SEARCHES_KEY, JSON.stringify(recents.slice(0, MAX_RECENT_SEARCHES))); } catch (_) {}
}

function clearSearchResultMarker() {
  if (searchResultMarker) { map.removeLayer(searchResultMarker); searchResultMarker = null; }
}

async function doSearch() {
  const q = searchInput.value.trim();
  if (!q) return;
  saveRecentSearch(q);
  searchResultsEl.innerHTML = '<div class="planner-search-result-note">Searching…</div>';
  try {
    const url = `https://photon.komoot.io/api/?limit=6&lat=${NZ_BIAS.lat}&lon=${NZ_BIAS.lon}&q=${encodeURIComponent(q)}`;
    const resp = await fetch(url);
    if (!resp.ok) throw new Error('search failed');
    const data = await resp.json();
    renderSearchResults(data.features || []);
  } catch (e) {
    searchResultsEl.innerHTML = '<div class="planner-search-result-note">Search failed. Try again.</div>';
  }
}

function placeLabel(props) {
  const suburb = props.district || props.suburb || props.neighbourhood;
  const city = props.city || props.town || props.village;
  const parts = [props.name, suburb, city, props.country].filter((v, i, arr) => v && arr.indexOf(v) === i);
  return parts.join(', ');
}

function renderSearchResults(features) {
  if (!features.length) {
    searchResultsEl.innerHTML = '<div class="planner-search-result-note">No results.</div>';
    return;
  }
  searchResultsEl.innerHTML = '';
  features.forEach(f => {
    const [lon, lat] = f.geometry.coordinates;
    const item = document.createElement('div');
    item.className = 'planner-search-result';
    item.textContent = placeLabel(f.properties) || `${lat.toFixed(4)}, ${lon.toFixed(4)}`;
    item.addEventListener('click', () => selectSearchResult(lat, lon, item.textContent));
    searchResultsEl.appendChild(item);
  });
}

// Shown when the search box is focused empty: quick access to current
// location and past searches, so search isn't a blank box every time.
function showSearchShortcuts() {
  searchResultsEl.innerHTML = '';
  const useLoc = document.createElement('div');
  useLoc.className = 'planner-search-result';
  useLoc.innerHTML = `${mlIconSVG('pin')} Use current location`;
  useLoc.addEventListener('click', useCurrentLocationAsResult);
  searchResultsEl.appendChild(useLoc);

  const recents = getRecentSearches();
  if (recents.length) {
    const label = document.createElement('div');
    label.className = 'planner-search-result-note';
    label.textContent = 'Recent searches';
    searchResultsEl.appendChild(label);
    recents.forEach(q => {
      const item = document.createElement('div');
      item.className = 'planner-search-result';
      item.textContent = q;
      item.addEventListener('click', () => { searchInput.value = q; doSearch(); });
      searchResultsEl.appendChild(item);
    });
  }
}

function useCurrentLocationAsResult() {
  if (!navigator.geolocation) { showToast('Geolocation is not supported on this device.', 'info'); return; }
  searchResultsEl.innerHTML = '<div class="planner-search-result-note">Locating…</div>';
  navigator.geolocation.getCurrentPosition(
    pos => selectSearchResult(pos.coords.latitude, pos.coords.longitude, 'Current location'),
    () => { searchResultsEl.innerHTML = '<div class="planner-search-result-note">Could not get your location.</div>'; },
    { timeout: 8000 }
  );
}

// A result was picked: preview it with a pin, then ask what it should become.
function selectSearchResult(lat, lon, label) {
  map.setView([lat, lon], 14);
  clearSearchResultMarker();
  searchResultMarker = L.marker([lat, lon], {
    icon: L.divIcon({ className: 'search-result-pin', html: mlIconSVG('pin'), iconSize: [26, 26], iconAnchor: [13, 26] })
  }).addTo(map);

  searchResultsEl.innerHTML = `
    <div class="planner-search-result-note">${escapeHtml(label)}</div>
    <div class="planner-search-action" data-action="start">Set as start</div>
    <div class="planner-search-action" data-action="stop">Add as stop</div>
    <div class="planner-search-action" data-action="destination">Set as destination</div>
    <div class="planner-search-action" data-action="view">Just view on map</div>
  `;
  searchResultsEl.querySelectorAll('.planner-search-action').forEach(el => {
    el.addEventListener('click', () => {
      applySearchAction(el.dataset.action, lat, lon);
      searchResultsEl.innerHTML = '';
      searchInput.value = '';
      if (el.dataset.action !== 'view') clearSearchResultMarker();
    });
  });
}

function applySearchAction(action, lat, lng) {
  if (action === 'view') return;
  if (action === 'start') {
    if (waypoints.length) { waypoints[0] = { lat, lng }; afterWaypointsChanged(); }
    else addWaypoint({ lat, lng });
  } else if (action === 'destination') {
    if (waypoints.length) { waypoints[waypoints.length - 1] = { lat, lng }; afterWaypointsChanged(); }
    else addWaypoint({ lat, lng });
  } else if (action === 'stop') {
    addWaypoint({ lat, lng });
  }
}

searchBtn.addEventListener('click', doSearch);
searchInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') { e.preventDefault(); doSearch(); }
});
searchInput.addEventListener('focus', () => {
  if (!searchInput.value.trim()) showSearchShortcuts();
});
document.addEventListener('click', (e) => {
  if (!e.target.closest('.planner-search')) {
    searchResultsEl.innerHTML = '';
    clearSearchResultMarker();
  }
});

// ---------- GPX export ----------
function escapeGpx(str) {
  return String(str).replace(/[<>&"]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
}
function buildRouteGPX(coords, title) {
  const pts = coords.map(c => `<rtept lat="${c[0]}" lon="${c[1]}"></rtept>`).join('\n        ');
  return `<?xml version="1.0"?>
<gpx version="1.1" creator="Memory Lanes Ride Journal" xmlns="http://www.topografix.com/GPX/1/1">
  <rte>
    <name>${escapeGpx(title)}</name>
        ${pts}
  </rte>
</gpx>`;
}
function downloadGPX(coords, title) {
  if (!coords || coords.length < 2) return;
  const safeTitle = title || 'Planned Route';
  const gpxString = buildRouteGPX(coords, safeTitle);
  const blob = new Blob([gpxString], { type: 'application/gpx+xml' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${safeTitle.replace(/\s+/g, '_')}.gpx`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
exportBtn.addEventListener('click', () => {
  downloadGPX(routeCoords, routeTitleInput.value.trim() || 'Planned Route');
});

// ---------- Save to Supabase ----------
function setSaveStatus(msg, isError) {
  saveStatusEl.textContent = msg;
  saveStatusEl.style.color = isError ? 'var(--color-danger)' : 'var(--color-success)';
}
saveBtn.addEventListener('click', async () => {
  const title = routeTitleInput.value.trim();
  if (!title) { setSaveStatus('Please enter a title.', true); return; }
  if (waypoints.length < 2 || routeCoords.length < 2) { setSaveStatus('Add at least two waypoints first.', true); return; }

  saveBtn.disabled = true;
  const original = saveBtn.textContent;
  saveBtn.textContent = 'Saving…';
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setSaveStatus('Please log in first.', true); return; }
    const { error } = await supabase.from('planned_routes').insert({
      user_id: user.id,
      title,
      distance_km: currentDistanceKm,
      elevation_m: currentElevationM,
      waypoints,
      route: routeCoords
    });
    if (error) throw error;
    setSaveStatus('Route saved!', false);
    routeTitleInput.value = '';
    await loadSavedRoutes();
  } catch (e) {
    setSaveStatus('Failed to save: ' + (e.message || e), true);
  } finally {
    saveBtn.textContent = original;
    updateButtons();
  }
});

// ---------- Saved routes list ----------
async function loadSavedRoutes() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;
  const { data, error } = await supabase
    .from('planned_routes')
    .select('id, title, distance_km, elevation_m, waypoints, route, created_at')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });
  if (error) {
    routesListEl.textContent = 'Unable to load your saved routes.';
    return;
  }
  savedRoutes = data || [];
  renderSavedRoutes();
}
function renderSavedRoutes() {
  if (!savedRoutes.length) {
    routesListEl.innerHTML = '<em>No planned routes yet. Build one above and save it.</em>';
    return;
  }
  routesListEl.innerHTML = '';
  savedRoutes.forEach(route => {
    const item = document.createElement('div');
    item.className = 'ride-entry';
    const created = route.created_at ? new Date(route.created_at).toLocaleDateString() : '';
    item.innerHTML = `
      <div class="ride-title-row">
        <div class="ride-title">${escapeHtml(route.title)}</div>
        <div class="ride-meta">
          <span class="ride-date">${created}</span>
        </div>
      </div>
      <div class="ride-details">
        <span>${mlIconSVG('pin')} ${route.distance_km ? route.distance_km.toFixed(1) : '--'} km</span>
        <span>${mlIconSVG('mountain')} ${route.elevation_m != null ? route.elevation_m : '--'} m</span>
      </div>
      <div class="planner-route-actions">
        <button type="button" class="btn-primary planner-start-btn">${mlIconSVG('play')} Start Ride</button>
        <button type="button" class="btn-outline planner-load-btn">${mlIconSVG('edit')} Load</button>
        <button type="button" class="btn-outline planner-export-saved-btn">${mlIconSVG('download')} Export GPX</button>
        <button type="button" class="btn-plain-danger planner-delete-btn">${mlIconSVG('trash')} Delete</button>
      </div>
    `;
    item.querySelector('.planner-start-btn').addEventListener('click', () => {
      window.location.href = `ride-live.html?route=${route.id}`;
    });
    item.querySelector('.planner-load-btn').addEventListener('click', () => loadSavedRouteIntoPlanner(route));
    item.querySelector('.planner-export-saved-btn').addEventListener('click', () => downloadGPX(route.route, route.title));
    item.querySelector('.planner-delete-btn').addEventListener('click', () => deleteSavedRoute(route.id));
    routesListEl.appendChild(item);
  });
}
function loadSavedRouteIntoPlanner(route) {
  onboardingEl.style.display = 'none';
  workspaceEl.style.display = '';
  setCropMode(false);
  setSplitMode(false);
  // A saved route's shape is already final — don't re-apply loop/return closing on top of it.
  routeType = 'one-way';
  waypoints = (route.waypoints || []).map(w => ({ lat: w.lat, lng: w.lng }));
  historyStack = [waypoints.map(w => ({ ...w }))];
  historyIndex = 0;
  routeTitleInput.value = route.title || '';
  fitOnNextDraw = true;
  rebuildMarkers();
  renderWaypointList();
  mapHint.style.display = waypoints.length ? 'none' : '';
  waypointCountEl.textContent = String(waypoints.length);
  updateButtons();
  updateGoalHint();
  scheduleRecalc(0);
  setTimeout(() => map.invalidateSize(), 50);
  window.scrollTo({ top: mapSection.offsetTop - 90, behavior: 'smooth' });
}
async function deleteSavedRoute(id) {
  if (!confirm('Delete this planned route? This cannot be undone.')) return;
  const { error } = await supabase.from('planned_routes').delete().eq('id', id);
  if (error) { showToast('Failed to delete route.', 'delete'); return; }
  savedRoutes = savedRoutes.filter(r => r.id !== id);
  renderSavedRoutes();
  showToast('Route deleted.', 'add');
}

// ---------- PWA: register the service worker ----------
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(err => console.warn('SW registration failed:', err));
  });
}
