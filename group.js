// ===============================
// Memory Lanes Ride Journal - group.js
// Group ride lobby + live spectator map. Anyone with the secret group link
// can watch; joining and riding needs an account. All riders who joined via
// this link broadcast onto this one shared map (that's the point — unlike
// route-copy sharing, there's a single shared ride object).
// ===============================

import supabase from './supabaseClient.js';

const loadingEl   = document.getElementById('group-loading');
const errorEl     = document.getElementById('group-error');
const bodyEl      = document.getElementById('group-body');
const titleEl     = document.getElementById('group-title');
const hostedByEl  = document.getElementById('group-hosted-by');
const routeLineEl = document.getElementById('group-route-line');
const liveBannerEl = document.getElementById('group-live-banner');
const distanceEl  = document.getElementById('group-distance');
const elevationEl = document.getElementById('group-elevation');
const membersEl   = document.getElementById('group-members');
const joinBtn     = document.getElementById('group-join-btn');
const copyBtn     = document.getElementById('group-copy-btn');
const endBtn      = document.getElementById('group-end-btn');
const loginNoteEl = document.getElementById('group-login-note');

const LIVE_POLL_MS = 15000;

let groupToken = null;
let groupRide = null;
let groupMap = null;
let riderMarkers = [];
let liveTimer = null;

function showError() {
  loadingEl.style.display = 'none';
  bodyEl.style.display = 'none';
  errorEl.style.display = '';
}

(async () => {
  groupToken = new URLSearchParams(window.location.search).get('ride');
  if (!groupToken) { showError(); return; }

  let gr = null;
  try {
    const { data, error } = await supabase.rpc('get_group_ride', { token: groupToken });
    if (error) throw error;
    gr = data;
  } catch (_) {
    showError();
    return;
  }
  if (!gr || !Array.isArray(gr.route) || gr.route.length < 2) { showError(); return; }

  groupRide = gr;
  loadingEl.style.display = 'none';
  bodyEl.style.display = '';

  titleEl.textContent = gr.title;
  if (gr.hosted_by) {
    hostedByEl.textContent = `Hosted by ${gr.hosted_by}`;
    hostedByEl.style.display = '';
  }
  routeLineEl.textContent = `Route: ${gr.route_title}`;
  distanceEl.textContent = gr.distance_km != null ? `${Number(gr.distance_km).toFixed(1)} km` : '–';
  elevationEl.textContent = gr.elevation_m != null ? `+${Math.round(gr.elevation_m)} m` : '–';
  membersEl.textContent = String(gr.member_count ?? 0);

  groupMap = L.map('group-map', { zoomControl: true });
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(groupMap);
  const line = L.polyline(gr.route, { color: '#64ffda', weight: 5, opacity: 0.9 }).addTo(groupMap);
  groupMap.fitBounds(line.getBounds(), { padding: [40, 40] });

  const { data: { user } } = await supabase.auth.getUser();
  if (user) {
    joinBtn.style.display = '';
    joinBtn.textContent = gr.is_member ? 'Start Riding' : 'Join & Start Riding';
    if (gr.is_owner) endBtn.style.display = '';
  } else {
    loginNoteEl.style.display = '';
  }

  startLivePolling();
})();

joinBtn.addEventListener('click', () => {
  // The ride tracker auto-joins via join_group_ride, so members and
  // first-timers take the same path.
  window.location.href = `ride-live.html?group=${groupToken}`;
});

copyBtn.addEventListener('click', async () => {
  const link = window.location.href;
  try {
    await navigator.clipboard.writeText(link);
    copyBtn.textContent = 'Link Copied!';
    setTimeout(() => { copyBtn.textContent = 'Copy Group Link'; }, 2000);
  } catch (_) {
    window.prompt('Copy this group ride link:', link);
  }
});

endBtn.addEventListener('click', async () => {
  if (!confirm('End this group ride? The link will stop working and live positions will disappear.')) return;
  const { error } = await supabase
    .from('group_rides')
    .update({ is_active: false })
    .eq('id', groupRide.id);
  if (error) { alert('Could not end the group ride: ' + error.message); return; }
  window.location.href = 'dashboard.html';
});

// ---------- Live riders ----------
async function refreshLiveRiders() {
  if (!groupToken || !groupMap) return;
  let riders = [];
  try {
    const { data, error } = await supabase.rpc('get_group_live_riders', { token: groupToken });
    if (error) throw error;
    riders = Array.isArray(data) ? data : [];
  } catch (_) {
    return; // transient failure — keep previous markers, retry next tick
  }

  riderMarkers.forEach(m => groupMap.removeLayer(m));
  riderMarkers = riders.map(r => {
    const marker = L.circleMarker([r.lat, r.lng], {
      radius: 9, color: '#ffd166', weight: 3, fillColor: '#ffd166', fillOpacity: 0.85
    }).addTo(groupMap);
    const speed = r.speed_kmh != null ? ` · ${Math.round(r.speed_kmh)} km/h` : '';
    marker.bindTooltip(`${r.name}${speed}`, { permanent: true, direction: 'top', offset: [0, -10], className: 'live-rider-label' });
    return marker;
  });

  if (riders.length) {
    liveBannerEl.textContent = riders.length === 1
      ? `${riders[0].name} is out riding right now`
      : `${riders.length} riders are out on this ride right now`;
    liveBannerEl.style.display = '';
  } else {
    liveBannerEl.style.display = 'none';
  }
}

function startLivePolling() {
  refreshLiveRiders();
  liveTimer = setInterval(refreshLiveRiders, LIVE_POLL_MS);
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

// ---------- PWA: register the service worker ----------
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(err => console.warn('SW registration failed:', err));
  });
}
