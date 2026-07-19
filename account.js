import supabase from './supabaseClient.js';

const elements = {
  avatar: document.getElementById('account-avatar'),
  name: document.getElementById('account-name'),
  email: document.getElementById('account-email'),
  region: document.getElementById('account-region'),
  rideCount: document.getElementById('account-ride-count'),
  distance: document.getElementById('account-distance'),
  profileToggle: document.getElementById('account-profile-toggle'),
  profileDetail: document.getElementById('account-profile-detail'),
  profileForm: document.getElementById('account-profile-form'),
  nameInput: document.getElementById('account-name-input'),
  regionInput: document.getElementById('account-region-input'),
  profileSave: document.getElementById('account-profile-save'),
  profileStatus: document.getElementById('account-profile-status'),
  groupSection: document.getElementById('account-group-section'),
  groupList: document.getElementById('account-group-list'),
  exportButton: document.getElementById('export-data-btn'),
  exportStatus: document.getElementById('account-export-status'),
  signOut: document.getElementById('account-sign-out')
};

let currentUser = null;
let rideRows = [];

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, character => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]
  ));
}

function fallbackName(email) {
  const localPart = String(email || '').split('@')[0];
  const words = localPart.replace(/[._-]+/g, ' ').trim().split(/\s+/).filter(Boolean);
  return words.map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ') || 'Rider';
}

function initials(name) {
  const letters = String(name || '').trim().split(/\s+/).slice(0, 2).map(word => word.charAt(0));
  return letters.join('').toUpperCase() || 'R';
}

function formatDistance(kilometres) {
  const value = Number(kilometres) || 0;
  return value >= 1000 ? `${(value / 1000).toFixed(1)}k km` : `${Math.round(value)} km`;
}

function renderIdentity(profile) {
  const displayName = profile?.display_name?.trim() || fallbackName(currentUser?.email);
  const region = profile?.region?.trim() || '';
  elements.name.textContent = displayName;
  elements.email.textContent = currentUser?.email || 'Signed-in rider';
  elements.avatar.textContent = initials(displayName);
  elements.nameInput.value = profile?.display_name || '';
  elements.regionInput.value = profile?.region || '';
  elements.profileDetail.textContent = region ? `${displayName} · ${region}` : displayName;
  elements.region.textContent = region;
  elements.region.hidden = !region;
}

async function loadProfile() {
  const { data } = await supabase
    .from('profiles')
    .select('display_name, region')
    .eq('user_id', currentUser.id)
    .maybeSingle();
  renderIdentity(data);
}

async function loadLibrary() {
  const { data, error } = await supabase
    .from('ride_logs')
    .select('*')
    .eq('user_id', currentUser.id)
    .order('ride_date', { ascending: false });
  if (error) throw error;
  rideRows = data || [];
  const totalDistance = rideRows.reduce((total, ride) => total + (Number(ride.distance_km) || 0), 0);
  elements.rideCount.textContent = String(rideRows.length);
  elements.distance.textContent = formatDistance(totalDistance);
}

async function loadGroupRides() {
  const { data, error } = await supabase.rpc('get_my_group_rides');
  if (error || !Array.isArray(data) || !data.length) return;
  elements.groupSection.hidden = false;
  elements.groupList.innerHTML = data.map(ride => {
    const role = ride.is_owner ? 'Hosting' : 'Riding';
    const detail = `${ride.member_count || 0} rider${ride.member_count === 1 ? '' : 's'} · ${role}`;
    return `<a class="account-row" href="group.html?ride=${encodeURIComponent(ride.share_token)}">
      <span class="account-row-icon" data-icon="flag"></span>
      <span><strong>${escapeHtml(ride.title || ride.route_title || 'Group ride')}</strong><small>${escapeHtml(detail)}</small></span>
      <span data-icon="chevron"></span>
    </a>`;
  }).join('');
  const { applyIcons } = await import('./icons.js?v=91');
  applyIcons();
}

elements.profileToggle.addEventListener('click', () => {
  const isOpen = !elements.profileForm.hidden;
  elements.profileForm.hidden = isOpen;
  elements.profileToggle.setAttribute('aria-expanded', String(!isOpen));
  if (!isOpen) elements.nameInput.focus();
});

elements.profileSave.addEventListener('click', async () => {
  elements.profileSave.disabled = true;
  elements.profileStatus.textContent = 'Saving…';
  const profile = {
    user_id: currentUser.id,
    display_name: elements.nameInput.value.trim(),
    region: elements.regionInput.value.trim(),
    updated_at: new Date().toISOString()
  };
  const { error } = await supabase.from('profiles').upsert(profile);
  elements.profileSave.disabled = false;
  if (error) {
    elements.profileStatus.textContent = `Could not save profile: ${error.message}`;
    return;
  }
  elements.profileStatus.textContent = 'Profile saved.';
  renderIdentity(profile);
  window.setTimeout(() => { elements.profileForm.hidden = true; }, 450);
});

elements.exportButton.addEventListener('click', async () => {
  if (elements.exportButton.disabled) return;
  if (typeof JSZip === 'undefined') {
    elements.exportStatus.textContent = 'Export tools did not load. Check your connection and try again.';
    return;
  }
  elements.exportButton.disabled = true;
  elements.exportStatus.textContent = 'Preparing your portable library…';
  try {
    const zip = new JSZip();
    zip.file('rides.json', JSON.stringify(rideRows, null, 2));
    zip.file('README.txt', `Memory Lanes data export\nExported: ${new Date().toISOString()}\n`);
    const tracks = rideRows.filter(ride => ride.gpx_path);
    let completed = 0;
    for (const ride of tracks) {
      const { data } = supabase.storage.from('gpx-files').getPublicUrl(ride.gpx_path);
      const response = await fetch(data.publicUrl);
      if (response.ok) {
        const name = (ride.title || 'ride').replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '_') || 'ride';
        zip.file(`gpx/${name}_${String(ride.id).slice(0, 8)}.gpx`, await response.blob());
      }
      completed += 1;
      elements.exportStatus.textContent = `Collecting GPX tracks ${completed}/${tracks.length}…`;
    }
    const blob = await zip.generateAsync({ type: 'blob' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `memory-lanes-export-${new Date().toISOString().slice(0, 10)}.zip`;
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 5000);
    elements.exportStatus.textContent = 'Your account export is ready.';
  } catch (error) {
    elements.exportStatus.textContent = `Export failed: ${error.message || error}`;
  } finally {
    elements.exportButton.disabled = false;
  }
});

elements.signOut.addEventListener('click', async () => {
  if (!window.confirm('Sign out of Memory Lanes? Your cloud rides will stay in your account.')) return;
  await supabase.auth.signOut();
  window.location.href = 'index.html';
});

(async () => {
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    window.location.href = 'index.html';
    return;
  }
  currentUser = user;
  renderIdentity(null);
  const results = await Promise.allSettled([loadProfile(), loadLibrary(), loadGroupRides()]);
  if (results[1].status === 'rejected') {
    elements.exportStatus.textContent = 'Your ride library could not be loaded. Refresh to try again.';
  }
})();

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(error => console.warn('SW registration failed:', error));
  });
}
