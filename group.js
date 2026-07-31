// ===============================
// Memory Lanes Ride Journal - group.js
// Group ride invite + member lobby. Invite details can be opened from the
// secret link, while attendee details and live positions remain restricted
// to authenticated members of the ride.
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
const openAppRowEl = document.getElementById('group-open-app-row');
const openAppBtn = document.getElementById('group-open-app-btn');
const checkInSectionEl = document.getElementById('group-check-in-section');
const checkInDetailEl = document.getElementById('group-check-in-detail');
const checkInBtn = document.getElementById('group-check-in-btn');
const meshSectionEl = document.getElementById('group-mesh-section');
const meshDetailEl = document.getElementById('group-mesh-detail');
const meshBtn = document.getElementById('group-mesh-btn');
const announcementsEl = document.getElementById('group-announcements');
const announcementListEl = document.getElementById('group-announcement-list');
const announcementComposerEl = document.getElementById('group-announcement-composer');
const announcementInput = document.getElementById('group-announcement-input');
const announcementBtn = document.getElementById('group-announcement-btn');
const announcementStatusEl = document.getElementById('group-announcement-status');
const leaveBtn = document.getElementById('group-leave-btn');

const LIVE_POLL_MS = 15000;
const IS_IOS = /iPhone|iPad|iPod/i.test(navigator.userAgent);

let groupToken = null;
let groupRide = null;
let currentUser = null;
let groupMap = null;
let riderMarkers = [];
let liveTimer = null;
let liveVisibilityListenerInstalled = false;

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
      <span class="group-attendee-name">
        ${escapeHtml(m.name)}${m.is_you ? ' (you)' : ''}
        ${m.checked_in_at ? '<small class="group-arrival-state">Checked in</small>' : ''}
      </span>
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

function canUseMemberFeatures() {
  return Boolean(currentUser && (groupRide?.is_owner || groupRide?.is_member));
}

function canUseRideMesh() {
  return Boolean(
    currentUser
      && groupRide?.status === 'scheduled'
      && groupRide?.is_active
      && (
        groupRide?.is_owner
        || (groupRide?.is_member && ['going', 'maybe'].includes(groupRide?.your_rsvp))
      )
  );
}

function canViewLiveRiders() {
  return Boolean(currentUser && (groupRide?.is_owner || groupRide?.your_rsvp === 'going'));
}

function rideMeshAppURL() {
  return `memorylanes://group/${groupToken}?open=mesh`;
}

function rideMeshWebURL() {
  const url = new URL(window.location.href);
  url.searchParams.set('ride', groupToken);
  url.searchParams.set('open', 'mesh');
  return url.href;
}

function renderRideMesh() {
  const available = canUseRideMesh();
  meshSectionEl.hidden = !available;
  if (!available) return;

  if (IS_IOS) {
    meshBtn.textContent = 'Open Ride Mesh';
    meshDetailEl.textContent = 'Open encrypted nearby messaging for this ride. Every nearby rider needs this group open in the iPhone app.';
  } else {
    meshBtn.textContent = 'Copy iPhone Link';
    meshDetailEl.textContent = 'Ride Mesh uses direct iPhone-to-iPhone links and cannot run inside a desktop browser. Send this link to each rider’s iPhone.';
  }
}

function renderCheckIn() {
  const visible = canUseMemberFeatures() && Boolean(groupRide.check_in_available);
  checkInSectionEl.hidden = !visible;
  if (!visible) return;

  const checkedIn = Boolean(groupRide.your_checked_in_at);
  checkInBtn.textContent = checkedIn ? 'Checked In' : "I'm Here";
  checkInBtn.classList.toggle('group-operation-active', checkedIn);
  checkInBtn.setAttribute('aria-pressed', String(checkedIn));
  checkInDetailEl.textContent = checkedIn
    ? 'The organiser can see that you have arrived.'
    : 'Check in when you reach the meeting point. This does not share your live location.';
}

function renderAnnouncements() {
  const announcements = Array.isArray(groupRide.announcements) ? groupRide.announcements : [];
  announcementsEl.hidden = !canUseMemberFeatures() || announcements.length === 0;
  announcementComposerEl.hidden = !currentUser || !groupRide.is_owner;

  announcementListEl.innerHTML = announcements.map(item => {
    const created = item.created_at ? new Date(item.created_at) : null;
    const time = created && !Number.isNaN(created.getTime())
      ? created.toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })
      : '';
    return `
      <article class="group-update">
        <div class="group-update-meta">
          <strong>${escapeHtml(item.author_name || 'Ride organiser')}</strong>
          <time>${escapeHtml(time)}</time>
        </div>
        <p>${escapeHtml(item.message)}</p>
      </article>
    `;
  }).join('');
}

function renderMemberOperations() {
  renderRideMesh();
  renderCheckIn();
  renderAnnouncements();
  leaveBtn.style.display = currentUser && groupRide.is_member && !groupRide.is_owner ? '' : 'none';
}

function renderAuthenticatedControls(syncEditor = false) {
  if (!currentUser) {
    joinBtn.style.display = 'none';
    rsvpRowEl.style.display = 'none';
    endBtn.style.display = 'none';
    meetEditorEl.style.display = 'none';
    renderMemberOperations();
    return;
  }

  joinBtn.style.display = '';
  joinBtn.textContent = groupRide.is_owner || groupRide.is_member
    ? 'Start Riding'
    : 'Join & Start Riding';

  // Hosts coordinate the ride; they are not also counted as an attendee RSVP.
  rsvpRowEl.style.display = groupRide.is_owner ? 'none' : '';
  renderRsvpButtons();

  if (groupRide.is_owner) {
    endBtn.style.display = '';
    meetEditorEl.style.display = '';
    if (syncEditor) {
      if (groupRide.meet_time) {
        const t = new Date(groupRide.meet_time);
        const pad = n => String(n).padStart(2, '0');
        meetTimeInput.value = `${t.getFullYear()}-${pad(t.getMonth() + 1)}-${pad(t.getDate())}T${pad(t.getHours())}:${pad(t.getMinutes())}`;
      } else {
        meetTimeInput.value = '';
      }
      meetPointInput.value = groupRide.meet_point || '';
    }
  } else {
    endBtn.style.display = 'none';
    meetEditorEl.style.display = 'none';
  }

  renderMemberOperations();
}

async function refreshGroupRideState() {
  if (!groupToken) return false;
  try {
    const rpcName = currentUser ? 'get_group_ride_operations' : 'get_group_ride';
    const { data, error } = await supabase.rpc(rpcName, { token: groupToken });
    if (error || !data) return false;
    groupRide = data;
    renderMeetLine();
    renderAttendees();
    renderAuthenticatedControls();
    return true;
  } catch (_) {
    return false;
  }
}

(async () => {
  groupToken = new URLSearchParams(window.location.search).get('ride');
  if (!groupToken) { showError(); return; }

  try {
    const { data } = await supabase.auth.getUser();
    currentUser = data?.user || null;
  } catch (_) {
    currentUser = null;
  }

  let gr = null;
  try {
    const rpcName = currentUser ? 'get_group_ride_operations' : 'get_group_ride';
    const { data, error } = await supabase.rpc(rpcName, { token: groupToken });
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

  if (IS_IOS) {
    openAppRowEl.style.display = '';
    openAppBtn.addEventListener('click', () => {
      const destination = new URLSearchParams(window.location.search).get('open') === 'mesh'
        ? rideMeshAppURL()
        : `memorylanes://group/${groupToken}`;
      window.location.href = destination;
    });
  }

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
  renderAuthenticatedControls(true);

  if (currentUser) {
    loginNoteEl.style.display = 'none';
  } else {
    loginNoteEl.style.display = '';
    // Remember this invite so logging in on the main page brings the rider
    // straight back to this lobby instead of stranding them on the landing page.
    try {
      localStorage.setItem('ml-pending-invite', JSON.stringify({ url: `group.html?ride=${groupToken}`, ts: Date.now() }));
    } catch (_) {}
  }

  if (canViewLiveRiders()) startLivePolling();
})();

meshBtn.addEventListener('click', async () => {
  if (!canUseRideMesh()) return;
  if (IS_IOS) {
    window.location.href = rideMeshAppURL();
    return;
  }

  const link = rideMeshWebURL();
  try {
    await navigator.clipboard.writeText(link);
    meshBtn.textContent = 'iPhone Link Copied';
    setTimeout(() => renderRideMesh(), 2000);
  } catch (_) {
    window.prompt('Open this link on each rider’s iPhone:', link);
  }
});

checkInBtn.addEventListener('click', async () => {
  if (!canUseMemberFeatures() || !groupRide.check_in_available || checkInBtn.disabled) return;
  checkInBtn.disabled = true;
  const checkedIn = !groupRide.your_checked_in_at;
  const { data, error } = await supabase.rpc('set_group_ride_check_in', {
    token: groupToken,
    checked_in: checkedIn
  });
  checkInBtn.disabled = false;
  if (error || !data) {
    checkInDetailEl.textContent = error?.message || 'Check-in could not be updated. Try again.';
    return;
  }
  groupRide = data;
  renderAttendees();
  renderCheckIn();
});

announcementBtn.addEventListener('click', async () => {
  const message = announcementInput.value.trim();
  if (!groupRide?.is_owner || !message || announcementBtn.disabled) return;
  announcementBtn.disabled = true;
  announcementStatusEl.textContent = 'Posting update...';
  const { data, error } = await supabase.rpc('post_group_ride_announcement', {
    token: groupToken,
    message
  });
  announcementBtn.disabled = false;
  if (error || !data) {
    announcementStatusEl.textContent = error?.message || 'The update could not be posted.';
    return;
  }
  groupRide = data;
  announcementInput.value = '';
  announcementStatusEl.textContent = 'Update posted.';
  renderAnnouncements();
});

leaveBtn.addEventListener('click', async () => {
  if (!groupRide?.is_member || groupRide?.is_owner || leaveBtn.disabled) return;
  if (!confirm('Leave this group ride? You can join again later while the invitation is open.')) return;
  leaveBtn.disabled = true;
  const { data, error } = await supabase.rpc('leave_group_ride', { token: groupToken });
  leaveBtn.disabled = false;
  if (error || !data) {
    alert(error?.message || 'The group ride could not be left. Try again.');
    return;
  }
  window.location.href = 'planner.html';
});

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
    if (btn.disabled) return;
    const answer = btn.dataset.rsvp;
    const buttons = Array.from(rsvpRowEl.querySelectorAll('.group-rsvp-btn'));
    buttons.forEach(button => { button.disabled = true; });
    const { data, error } = await supabase.rpc('rsvp_group_ride', { token: groupToken, answer });
    buttons.forEach(button => { button.disabled = false; });
    if (error || !data) {
      alert('Could not save your answer. Are you logged in?');
      return;
    }
    groupRide = data;
    await refreshGroupRideState();
    if (canViewLiveRiders()) startLivePolling();
    else stopLivePolling();
  });
});

joinBtn.addEventListener('click', () => {
  // The ride tracker auto-joins via join_group_ride, so members and
  // first-timers take the same path.
  window.location.href = `ride-live.html?group=${groupToken}`;
});

copyBtn.addEventListener('click', async () => {
  const url = new URL(window.location.href);
  url.search = '';
  url.searchParams.set('ride', groupToken);
  const link = url.href;
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
  endBtn.disabled = true;
  const { data, error } = await supabase.rpc('set_group_ride_status', {
    token: groupToken,
    new_status: 'cancelled'
  });
  endBtn.disabled = false;
  if (error || !data) {
    alert('Could not end the group ride: ' + (error?.message || 'Try again.'));
    return;
  }
  window.location.href = 'planner.html';
});

// ---------- Live refresh (rider markers + RSVPs) ----------
// The host sees answers arrive as they happen: each tick also re-reads the
// group ride so the Who's coming list and rider count stay current without
// a manual refresh. Display-only fields are updated; the host's meeting
// editor inputs are left alone so typing is never clobbered.
async function refreshAttendees() {
  await refreshGroupRideState();
}

async function refreshLiveRiders() {
  if (!groupToken || !groupMap) return;
  await refreshAttendees();
  if (!canViewLiveRiders()) {
    stopLivePolling();
    return;
  }
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
  if (liveTimer || !canViewLiveRiders()) return;
  refreshLiveRiders();
  liveTimer = setInterval(refreshLiveRiders, LIVE_POLL_MS);

  if (!liveVisibilityListenerInstalled) {
    liveVisibilityListenerInstalled = true;
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') {
        clearInterval(liveTimer);
        liveTimer = null;
      } else if (!liveTimer && canViewLiveRiders()) {
        refreshLiveRiders();
        liveTimer = setInterval(refreshLiveRiders, LIVE_POLL_MS);
      }
    });
  }
}

function stopLivePolling() {
  if (liveTimer) clearInterval(liveTimer);
  liveTimer = null;
  riderMarkers.forEach(marker => groupMap?.removeLayer(marker));
  riderMarkers = [];
  liveBannerEl.style.display = 'none';
}

// ---------- PWA: register the service worker ----------
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(err => console.warn('SW registration failed:', err));
  });
}
