// ===============================
// Memory Lanes Ride Journal - planner.js
// Plan a route on the map (click to add waypoints, snapped to real roads
// via OSRM), preview distance/elevation, then save it or export a GPX.
// ===============================

import supabase from './supabaseClient.js';
import { mlIconSVG } from './icons.js?v=58';

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
  await loadSavedRoutes();
})();

if (dashboardBtn) {
  dashboardBtn.addEventListener('click', () => { window.location.href = 'dashboard.html'; });
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
  map.on('click', (e) => addWaypoint(e.latlng));
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
  afterWaypointsChanged();
});

function updateButtons() {
  undoBtn.disabled = historyIndex <= 0;
  redoBtn.disabled = historyIndex >= historyStack.length - 1;
  clearBtn.disabled = waypoints.length === 0;
  const enoughPoints = waypoints.length >= 2;
  saveBtn.disabled = !enoughPoints;
  exportBtn.disabled = !enoughPoints;
}

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
    return;
  }

  recalcAbort = new AbortController();
  const signal = recalcAbort.signal;
  setElevationText('loading');

  let coords, distanceKm, fallback = false;
  try {
    const coordStr = waypoints.map(w => `${w.lng},${w.lat}`).join(';');
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
    coords = waypoints.map(w => [w.lat, w.lng]);
    distanceKm = straightLineDistanceKm(waypoints);
  }

  routeCoords = coords;
  drawRouteLine(coords, fallback, fitOnNextDraw);
  fitOnNextDraw = false;
  setDistanceText(distanceKm);

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

// ---------- Search (Nominatim geocoding, pans the map only) ----------
async function doSearch() {
  const q = searchInput.value.trim();
  if (!q) return;
  searchResultsEl.innerHTML = '<div class="planner-search-result-note">Searching…</div>';
  try {
    const url = `https://nominatim.openstreetmap.org/search?format=json&limit=5&q=${encodeURIComponent(q)}`;
    const resp = await fetch(url);
    const data = await resp.json();
    renderSearchResults(data);
  } catch (e) {
    searchResultsEl.innerHTML = '<div class="planner-search-result-note">Search failed. Try again.</div>';
  }
}
function renderSearchResults(results) {
  if (!results || !results.length) {
    searchResultsEl.innerHTML = '<div class="planner-search-result-note">No results.</div>';
    return;
  }
  searchResultsEl.innerHTML = '';
  results.forEach(r => {
    const item = document.createElement('div');
    item.className = 'planner-search-result';
    item.textContent = r.display_name;
    item.addEventListener('click', () => {
      map.setView([parseFloat(r.lat), parseFloat(r.lon)], 13);
      searchResultsEl.innerHTML = '';
      searchInput.value = '';
    });
    searchResultsEl.appendChild(item);
  });
}
searchBtn.addEventListener('click', doSearch);
searchInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') { e.preventDefault(); doSearch(); }
});
document.addEventListener('click', (e) => {
  if (!e.target.closest('.planner-search')) searchResultsEl.innerHTML = '';
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
        <button type="button" class="btn-outline planner-load-btn">${mlIconSVG('edit')} Load</button>
        <button type="button" class="btn-outline planner-export-saved-btn">${mlIconSVG('download')} Export GPX</button>
        <button type="button" class="btn-plain-danger planner-delete-btn">${mlIconSVG('trash')} Delete</button>
      </div>
    `;
    item.querySelector('.planner-load-btn').addEventListener('click', () => loadSavedRouteIntoPlanner(route));
    item.querySelector('.planner-export-saved-btn').addEventListener('click', () => downloadGPX(route.route, route.title));
    item.querySelector('.planner-delete-btn').addEventListener('click', () => deleteSavedRoute(route.id));
    routesListEl.appendChild(item);
  });
}
function loadSavedRouteIntoPlanner(route) {
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
  scheduleRecalc(0);
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
