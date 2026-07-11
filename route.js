// ===============================
// Memory Lanes Ride Journal - route.js
// Shared-route invite page: anyone with the secret link can view a planned
// route (via the get_shared_route SECURITY DEFINER function — no login
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
const exportBtn   = document.getElementById('route-export-btn');
const saveStatusEl = document.getElementById('route-save-status');
const loginNoteEl  = document.getElementById('route-login-note');

let sharedRoute = null;

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
  loadingEl.style.display = 'none';
  bodyEl.style.display = '';

  titleEl.textContent = route.title || 'Shared Route';
  distanceEl.textContent = route.distance_km != null ? `${Number(route.distance_km).toFixed(1)} km` : '–';
  elevationEl.textContent = route.elevation_m != null ? `+${Math.round(route.elevation_m)} m` : '–';
  waypointsEl.textContent = Array.isArray(route.waypoints) ? String(route.waypoints.length) : '–';

  const map = L.map('route-map', { zoomControl: true });
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);
  const line = L.polyline(route.route, { color: '#64ffda', weight: 5, opacity: 0.9 }).addTo(map);
  map.fitBounds(line.getBounds(), { padding: [40, 40] });

  // Saving needs an account; viewing doesn't. Decide which affordance to show.
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    saveBtn.disabled = true;
    loginNoteEl.style.display = '';
  }
})();

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
    saveStatusEl.textContent = 'Saved to your routes!';
    saveStatusEl.style.color = 'var(--color-success)';
    saveBtn.textContent = 'Saved';
    // Straight into their own editable copy.
    window.location.href = `planner.html?load=${data.id}`;
  } catch (e) {
    saveStatusEl.textContent = 'Could not save: ' + (e.message || e);
    saveStatusEl.style.color = 'var(--color-danger)';
    saveBtn.disabled = false;
    saveBtn.textContent = original;
  }
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
