// ===============================
// Memory Lanes Ride Journal - group.js
// Group ride lobby + live spectator map. Anyone with the secret group link
// can watch; joining and riding needs an account. All riders who joined via
// this link broadcast onto this one shared map (that's the point - unlike
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
const meetLineEl  = document.getElementById('group-meet-line');
const meetEditorEl = document.getElementById('group-meet-editor');
const meetTimeInput = document.getElementById('group-meet-time-input');
const meetPointInput = document.getElementById('group-meet-point-input');
const meetSaveBtn = document.getElementById('group-meet-save-btn');
const meetStatusEl = document.getElementById('group-meet-status');
const rsvpRowEl   = document.getElementById('group-rsvp-row');
const attendeesEl = document.getElementById('group-attendees');
const attendeeListEl = document.getElementById('group-attendee-list');

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

function escapeHtml(str) {
  return String(str ?? '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
  );
}

const RSVP_LABELS = { going: 'Riding', maybe: 'Maybe', no: 'Not this time' };

function renderMeetLine() {
  const parts = [];
  if (groupRide.meet_time) {
    const t = new Date(groupRide.meet_time);
    parts.push(`Meets ${t.toLocaleDateString()} at ${t.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`);
  }
  if (groupRide.meet_point) parts.push(groupRide.meet_time ? `from ${groupRide.meet_point}` : `Meeting point: ${groupRide.meet_point}`);
  if (parts.length) {
    meetLineEl.textContent = parts.join(' ');
    meetLineEl.style.display = '';
  } else {
    meetLineEl.style.display = 'none';
  }
}

function renderAttendees() {
  const members = Array.isArray(groupRide.members) ? groupRide.members : [];
  if (!members.length) { attendeesEl.style.display = 'none'; return; }
  attendeesEl.style.display = '';
  attendeeListEl.innerHTML = members.map(m => `
    <div class="group-attendee">
      <span class="group-attendee-name">${escapeHtml(m.name)}${m.is_you ? ' (you)' : ''}</span>
      <span class="status-chip ${m.rsvp === 'going' ? 'status-chip-completed' : m.rsvp === 'maybe' ? 'status-chip-planned' : 'status-chip-shared'}">${RSVP_LABELS[m.rsvp] || m.rsvp}</span>
    </div>
  `).join('');
  membersEl.textContent = String(members.filter(m => m.rsvp !== 'no').length);
}

function renderRsvpButtons() {
  rsvpRowEl.querySelectorAll('.group-rsvp-btn').forEach(btn => {
    btn.classList.toggle('active-rsvp', btn.dataset.rsvp === groupRide.your_rsvp);
  });
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

  renderMeetLine();
  renderAttendees();

  const { data: { user } } = await supabase.auth.getUser();
  if (user) {
    joinBtn.style.display = '';
    joinBtn.textContent = gr.is_member ? 'Start Riding' : 'Join & Start Riding';
    rsvpRowEl.style.display = '';
    renderRsvpButtons();
    if (gr.is_owner) {
      endBtn.style.display = '';
      meetEditorEl.style.display = '';
      if (gr.meet_time) {
        // datetime-local wants local time without the timezone suffix
        const t = new Date(gr.meet_time);
        const pad = n => String(n).padStart(2, '0');
        meetTimeInput.value = `${t.getFullYear()}-${pad(t.getMonth() + 1)}-${pad(t.getDate())}T${pad(t.getHours())}:${pad(t.getMinutes())}`;
      }
      meetPointInput.value = gr.meet_point || '';
    }
  } else {
    loginNoteEl.style.display = '';
    // Remember this invite so logging in on the main page brings the rider
    // straight back to this lobby instead of stranding them on the landing page.
    try {
      localStorage.setItem('ml-pending-invite', JSON.stringify({ url: `group.html?ride=${groupToken}`, ts: Date.now() }));
    } catch (_) {}
  }

  startLivePolling();
})();

meetSaveBtn.addEventListener('click', async () => {
  meetSaveBtn.disabled = true;
  meetStatusEl.textContent = 'Saving...';
  const meet_time = meetTimeInput.value ? new Date(meetTimeInput.value).toISOString() : null;
  const meet_point = meetPointInput.value.trim() || null;
  const { error } = await supabase
    .from('group_rides')
    .update({ meet_time, meet_point })
    .eq('id', groupRide.id);
  meetSaveBtn.disabled = false;
  if (error) {
    meetStatusEl.textContent = 'Could not save: ' + error.message;
    return;
  }
  meetStatusEl.textContent = 'Meeting details saved.';
  groupRide.meet_time = meet_time;
  groupRide.meet_point = meet_point;
  renderMeetLine();
});

rsvpRowEl.querySelectorAll('.group-rsvp-btn').forEach(btn => {
  btn.addEventListener('click', async () => {
    const answer = btn.dataset.rsvp;
    const { data, error } = await supabase.rpc('rsvp_group_ride', { token: groupToken, answer });
    if (error || !data) {
      alert('Could not save your answer. Are you logged in?');
      return;
    }
    groupRide = data;
    renderMeetLine();
    renderAttendees();
    renderRsvpButtons();
    joinBtn.textContent = 'Start Riding'; // rsvp created the membership if it didn't exist
  });
});

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

// ---------- Live refresh (rider markers + RSVPs) ----------
// The host sees answers arrive as they happen: each tick also re-reads the
// group ride so the Who's coming list and rider count stay current without
// a manual refresh. Display-only fields are updated; the host's meeting
// editor inputs are left alone so typing is never clobbered.
async function refreshAttendees() {
  try {
    const { data, error } = await supabase.rpc('get_group_ride', { token: groupToken });
    if (error || !data) return;
    groupRide.members = data.members;
    groupRide.member_count = data.member_count;
    groupRide.meet_time = data.meet_time;
    groupRide.meet_point = data.meet_point;
    groupRide.your_rsvp = data.your_rsvp;
    renderMeetLine();
    renderAttendees();
    renderRsvpButtons();
  } catch (_) { /* transient failure - retry next tick */ }
}

async function refreshLiveRiders() {
  if (!groupToken || !groupMap) return;
  refreshAttendees();
  let riders = [];
  try {
    const { data, error } = await supabase.rpc('get_group_live_riders', { token: groupToken });
    if (error) throw error;
    riders = Array.isArray(data) ? data : [];
  } catch (_) {
    return; // transient failure - keep previous markers, retry next tick
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
