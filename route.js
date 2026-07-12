// ===============================
// Memory Lanes Ride Journal - route.js
// Shared-route invite page: anyone with the secret link can view a planned
// route (via the get_shared_route SECURITY DEFINER function - no login
// needed), and a logged-in rider can save a copy into their own library.
// The owner stays anonymous: user_id never leaves the database.
// ===============================

import supabase from './supabaseClient.js';

const loadingEl   = document.getElementById('route-loading');
const errorEl     = document.getElementById('route-error');
const bodyEl      = document.getElementById('route-body');
const titleEl     = document.getElementById('route-title');
const distanceEl  = document.getElementById('route-distance');
const elevationEl = document.getElementById('route-elevation');
const waypointsEl = document.getElementById('route-waypoints');
const saveBtn     = document.getElementById('route-save-btn');
const declineBtn  = document.getElementById('route-decline-btn');
const exportBtn   = document.getElementById('route-export-btn');
const saveStatusEl = document.getElementById('route-save-status');
const loginNoteEl  = document.getElementById('route-login-note');
const sharedByEl   = document.getElementById('route-shared-by');
const liveBannerEl = document.getElementById('route-live-banner');

let sharedRoute = null;
let shareToken = null;
let routeMap = null;
let liveRiderMarkers = [];
let liveTimer = null;

function escapeGpx(str) {
  return String(str).replace(/[<>&"]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
}

function showError() {
  loadingEl.style.display = 'none';
  bodyEl.style.display = 'none';
  errorEl.style.display = '';
}

(async () => {
  const token = new URLSearchParams(window.location.search).get('share');
  if (!token) { showError(); return; }

  let route = null;
  try {
    const { data, error } = await supabase.rpc('get_shared_route', { token });
    if (error) throw error;
    route = data;
  } catch (e) {
    showError();
    return;
  }
  if (!route || !Array.isArray(route.route) || route.route.length < 2) { showError(); return; }

  sharedRoute = route;
  shareToken = token;
  loadingEl.style.display = 'none';
  bodyEl.style.display = '';

  titleEl.textContent = route.title || 'Shared Route';
  if (route.shared_by) {
    sharedByEl.textContent = `Shared by ${route.shared_by}${route.shared_by_region ? ` · ${route.shared_by_region}` : ''}`;
    sharedByEl.style.display = '';
  }
  distanceEl.textContent = route.distance_km != null ? `${Number(route.distance_km).toFixed(1)} km` : '–';
  elevationEl.textContent = route.elevation_m != null ? `+${Math.round(route.elevation_m)} m` : '–';
  waypointsEl.textContent = Array.isArray(route.waypoints) ? String(route.waypoints.length) : '–';

  routeMap = L.map('route-map', { zoomControl: true });
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(routeMap);
  const line = L.polyline(route.route, { color: '#64ffda', weight: 5, opacity: 0.9 }).addTo(routeMap);
  routeMap.fitBounds(line.getBounds(), { padding: [40, 40] });

  startLiveRiderPolling();

  // Saving needs an account; viewing doesn't. Decide which affordance to show.
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    saveBtn.disabled = true;
    loginNoteEl.style.display = '';
    // Remember this invite so logging in on the main page brings the rider
    // straight back here instead of stranding them on the landing page.
    try {
      localStorage.setItem('ml-pending-invite', JSON.stringify({ url: `route.html?share=${token}`, ts: Date.now() }));
    } catch (_) {}
  }
})();

// ---------- Live riders (opt-in broadcasters currently on this route) ----------
// Riders only appear if they switched on "broadcast my position" for this
// ride, and the server only answers for the same secret token that unlocked
// the route itself. Stale positions (>5 min) are filtered out server-side.
const LIVE_POLL_MS = 15000;

async function refreshLiveRiders() {
  if (!shareToken || !routeMap) return;
  let riders = [];
  try {
    const { data, error } = await supabase.rpc('get_live_riders', { token: shareToken });
    if (error) throw error;
    riders = Array.isArray(data) ? data : [];
  } catch (_) {
    return; // transient network issue - keep the previous markers, try again next tick
  }

  liveRiderMarkers.forEach(m => routeMap.removeLayer(m));
  liveRiderMarkers = riders.map(r => {
    const marker = L.circleMarker([r.lat, r.lng], {
      radius: 9, color: '#ffd166', weight: 3, fillColor: '#ffd166', fillOpacity: 0.85
    }).addTo(routeMap);
    const speed = r.speed_kmh != null ? ` · ${Math.round(r.speed_kmh)} km/h` : '';
    marker.bindTooltip(`${r.name}${speed}`, { permanent: true, direction: 'top', offset: [0, -10], className: 'live-rider-label' });
    return marker;
  });

  if (riders.length) {
    liveBannerEl.textContent = riders.length === 1
      ? `${riders[0].name} is riding this route right now`
      : `${riders.length} riders are on this route right now`;
    liveBannerEl.style.display = '';
  } else {
    liveBannerEl.style.display = 'none';
  }
}

function startLiveRiderPolling() {
  refreshLiveRiders();
  liveTimer = setInterval(refreshLiveRiders, LIVE_POLL_MS);
  // Don't poll a hidden tab; refresh immediately when it comes back.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      clearInterval(liveTimer);
      liveTimer = null;
    } else if (!liveTimer) {
      refreshLiveRiders();
      liveTimer = setInterval(refreshLiveRiders, LIVE_POLL_MS);
    }
  });
}

saveBtn.addEventListener('click', async () => {
  if (!sharedRoute) return;
  saveBtn.disabled = true;
  const original = saveBtn.textContent;
  saveBtn.textContent = 'Saving…';
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      loginNoteEl.style.display = '';
      return;
    }
    const { data, error } = await supabase
      .from('planned_routes')
      .insert({
        user_id: user.id,
        title: sharedRoute.title || 'Shared Route',
        distance_km: sharedRoute.distance_km,
        elevation_m: sharedRoute.elevation_m,
        waypoints: sharedRoute.waypoints,
        route: sharedRoute.route
      })
      .select('id')
      .single();
    if (error) throw error;
    try { localStorage.removeItem('ml-pending-invite'); } catch (_) {}
    saveStatusEl.textContent = 'Accepted! This route is now in your planned routes. Opening your journal...';
    saveStatusEl.style.color = 'var(--color-success)';
    saveBtn.textContent = 'Accepted';
    // Land on the journal so the new Planned card is immediately visible.
    setTimeout(() => { window.location.href = 'dashboard.html'; }, 900);
  } catch (e) {
    saveStatusEl.textContent = 'Could not save: ' + (e.message || e);
    saveStatusEl.style.color = 'var(--color-danger)';
    saveBtn.disabled = false;
    saveBtn.textContent = original;
  }
});

declineBtn.addEventListener('click', async () => {
  try { localStorage.removeItem('ml-pending-invite'); } catch (_) {}
  const { data: { user } } = await supabase.auth.getUser();
  window.location.href = user ? 'dashboard.html' : 'index.html';
});

exportBtn.addEventListener('click', () => {
  if (!sharedRoute || !Array.isArray(sharedRoute.route) || sharedRoute.route.length < 2) return;
  const title = sharedRoute.title || 'Shared Route';
  const pts = sharedRoute.route.map(c => `<rtept lat="${c[0]}" lon="${c[1]}"></rtept>`).join('\n        ');
  const gpx = `<?xml version="1.0"?>
<gpx version="1.1" creator="Memory Lanes Ride Journal" xmlns="http://www.topografix.com/GPX/1/1">
  <rte>
    <name>${escapeGpx(title)}</name>
        ${pts}
  </rte>
</gpx>`;
  const blob = new Blob([gpx], { type: 'application/gpx+xml' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${title.replace(/\s+/g, '_')}.gpx`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
});

// ---------- PWA: register the service worker ----------
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(err => console.warn('SW registration failed:', err));
  });
}
