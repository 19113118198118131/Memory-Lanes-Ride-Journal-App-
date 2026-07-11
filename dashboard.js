// ===============================
// Memory Lanes Ride Journal - dashboard.js
// Shows two distinct kinds of item: planned routes (not ridden yet) and
// completed rides (recorded/uploaded), each with their own card layout
// and a status chip, merged into one chronological journal list.
// ===============================

// Supabase config
import supabase from './supabaseClient.js';
import { mlIconSVG } from './icons.js?v=74';

// DOM references
const rideList = document.getElementById('ride-list');
const logoutBtn = document.getElementById('logout-btn');
const newRideBtn = document.getElementById('home-btn');

// --- Filters UI container setup (above the ride list) ---
const filtersContainer = document.createElement('div');
filtersContainer.className = 'filters-container';
filtersContainer.innerHTML = `
  <div class="ride-filters">
    <label for="sort-select">Sort by:</label>
    <select id="sort-select">
      <option value="date_desc">Newest First</option>
      <option value="date_asc">Oldest First</option>
      <option value="distance_desc">Longest</option>
      <option value="distance_asc">Shortest</option>
      <option value="elevation_desc">Most Elevation</option>
      <option value="elevation_asc">Least Elevation</option>
    </select>
    <input type="text" id="searchInput" placeholder="Search title..." />
    <select id="monthFilter">
      <option value="">All Months</option>
    </select>
    <select id="yearFilter">
      <option value="">All Years</option>
    </select>
    <select id="typeFilter">
      <option value="">Planned + Completed</option>
      <option value="planned">Planned Only</option>
      <option value="ride">Completed Only</option>
    </select>
  </div>
`;
rideList.parentElement.insertBefore(filtersContainer, rideList);

let allItems = [];

// Escape user-entered text before injecting into innerHTML
function escapeHtml(str) {
  return String(str ?? '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
  );
}

// ========== Main initialization ==========
(async () => {
  // Get logged-in user, redirect to login if not authenticated
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    window.location.href = 'index.html';
    return;
  }

  const [ridesRes, plannedRes] = await Promise.all([
    supabase
      .from('ride_logs')
      .select('id, title, distance_km, duration_min, elevation_m, ride_date, gpx_path, moments, is_public, skills')
      .eq('user_id', user.id)
      .order('ride_date', { ascending: false }),
    supabase
      .from('planned_routes')
      .select('id, title, distance_km, elevation_m, waypoints, route, created_at, is_public, share_token')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
  ]);

  if (ridesRes.error) {
    showToast('Failed to load rides.', 'delete');
  }
  // planned_routes may not exist yet if that migration hasn't been run — fail soft.
  const plannedRows = plannedRes.error ? [] : (plannedRes.data || []);

  const rides = (ridesRes.data || []).map(r => ({ ...r, _type: 'ride', _date: r.ride_date }));
  const planned = plannedRows.map(r => ({ ...r, _type: 'planned', _date: r.created_at }));

  if (ridesRes.error && plannedRes.error) {
    rideList.textContent = 'Unable to load your journal. Please try again.';
    return;
  }

  allItems = [...rides, ...planned];

  initProfileEditor(user);

  populateMonthFilter(allItems);
  populateYearFilter(allItems);
  renderItems(allItems);

  // --- Attach filter and sort events ---
  document.getElementById('searchInput').addEventListener('input', applyFilters);
  document.getElementById('monthFilter').addEventListener('change', applyFilters);
  document.getElementById('yearFilter').addEventListener('change', applyFilters);
  document.getElementById('sort-select').addEventListener('change', applyFilters);
  document.getElementById('typeFilter').addEventListener('change', applyFilters);
})();

// ========== Rider profile (name shown on shared-route invites) ==========
async function initProfileEditor(user) {
  const summaryEl = document.getElementById('profile-summary');
  const formEl = document.getElementById('profile-form');
  const toggleBtn = document.getElementById('profile-toggle-btn');
  const nameInput = document.getElementById('profile-name-input');
  const regionInput = document.getElementById('profile-region-input');
  const saveBtn = document.getElementById('profile-save-btn');
  const statusEl = document.getElementById('profile-status');
  if (!summaryEl || !formEl) return;

  function renderSummary(name, region) {
    if (name) {
      summaryEl.textContent = `Sharing routes as "${name}"${region ? ` · ${region}` : ''}.`;
    } else {
      summaryEl.textContent = 'No display name set — your shared routes show no name. Add one so invites can say who they\'re from.';
    }
  }

  // profiles may not exist if the migration hasn't run — fail soft like planned_routes does.
  let profile = null;
  try {
    const { data } = await supabase.from('profiles').select('display_name, region').eq('user_id', user.id).maybeSingle();
    profile = data;
  } catch (_) {}
  nameInput.value = profile?.display_name || '';
  regionInput.value = profile?.region || '';
  renderSummary(nameInput.value.trim(), regionInput.value.trim());

  toggleBtn.addEventListener('click', () => {
    const open = formEl.style.display !== 'none';
    formEl.style.display = open ? 'none' : '';
    toggleBtn.textContent = open ? 'Edit' : 'Close';
  });

  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true;
    statusEl.textContent = 'Saving…';
    const display_name = nameInput.value.trim();
    const region = regionInput.value.trim();
    const { error } = await supabase
      .from('profiles')
      .upsert({ user_id: user.id, display_name, region, updated_at: new Date().toISOString() });
    saveBtn.disabled = false;
    if (error) {
      statusEl.textContent = 'Could not save profile: ' + error.message;
      return;
    }
    statusEl.textContent = 'Profile saved.';
    renderSummary(display_name, region);
  });
}

// ========== Filtering & Sorting ==========
function applyFilters() {
  const keyword = document.getElementById('searchInput').value.toLowerCase();
  const month = document.getElementById('monthFilter').value;
  const year = document.getElementById('yearFilter').value;
  const sort = document.getElementById('sort-select').value;
  const type = document.getElementById('typeFilter').value;

  let filtered = allItems.filter(item => {
    const matchesKeyword = (item.title || '').toLowerCase().includes(keyword);
    const itemDate = item._date ? new Date(item._date) : null;
    const matchesMonth = !month || (itemDate && itemDate.getMonth() === Number(month));
    const matchesYear = !year || (itemDate && itemDate.getFullYear().toString() === year);
    const matchesType = !type || item._type === type;
    return matchesKeyword && matchesMonth && matchesYear && matchesType;
  });

  switch (sort) {
    case 'date_asc':
      filtered.sort((a, b) => new Date(a._date) - new Date(b._date));
      break;
    case 'date_desc':
      filtered.sort((a, b) => new Date(b._date) - new Date(a._date));
      break;
    case 'distance_asc':
      filtered.sort((a, b) => (a.distance_km || 0) - (b.distance_km || 0));
      break;
    case 'distance_desc':
      filtered.sort((a, b) => (b.distance_km || 0) - (a.distance_km || 0));
      break;
    case 'elevation_asc':
      filtered.sort((a, b) => (a.elevation_m || 0) - (b.elevation_m || 0));
      break;
    case 'elevation_desc':
      filtered.sort((a, b) => (b.elevation_m || 0) - (a.elevation_m || 0));
      break;
  }

  renderItems(filtered);
}

// ========== Populate Month & Year Filter Dropdowns ==========
function populateMonthFilter(items) {
  const monthFilter = document.getElementById('monthFilter');
  monthFilter.innerHTML = '<option value="">All Months</option>';
  const monthSet = new Set();
  items.forEach(item => {
    if (item._date) monthSet.add(new Date(item._date).getMonth());
  });
  [...monthSet].sort((a, b) => a - b).forEach(m => {
    const opt = document.createElement('option');
    opt.value = m;
    opt.textContent = new Date(2025, m).toLocaleString('default', { month: 'long' });
    monthFilter.appendChild(opt);
  });
}

function populateYearFilter(items) {
  const yearFilter = document.getElementById('yearFilter');
  yearFilter.innerHTML = '<option value="">All Years</option>';
  const yearSet = new Set();
  items.forEach(item => {
    if (item._date) yearSet.add(new Date(item._date).getFullYear());
  });
  [...yearSet].sort((a, b) => a - b).forEach(y => {
    const opt = document.createElement('option');
    opt.value = y;
    opt.textContent = y;
    yearFilter.appendChild(opt);
  });
}

// ========== Deletion ==========
async function deleteRide(rideId, gpxPath) {
  const confirmed = window.confirm('Are you sure you want to delete this ride? This cannot be undone.');
  if (!confirmed) return;

  const { error: deleteError } = await supabase.from('ride_logs').delete().eq('id', rideId);
  if (deleteError) {
    showToast(`Failed to delete ride: ${deleteError.message}`, 'delete');
    return;
  }
  if (gpxPath) {
    const { error: storageError } = await supabase.storage.from('gpx-files').remove([gpxPath]);
    if (storageError) console.warn('GPX file deletion failed:', storageError.message);
  }
  allItems = allItems.filter(item => !(item._type === 'ride' && item.id === rideId));
  applyFilters();
  showToast('Ride deleted.', 'add');
}

async function deletePlannedRoute(routeId) {
  const confirmed = window.confirm('Delete this planned route? This cannot be undone.');
  if (!confirmed) return;

  const { error } = await supabase.from('planned_routes').delete().eq('id', routeId);
  if (error) {
    showToast(`Failed to delete route: ${error.message}`, 'delete');
    return;
  }
  allItems = allItems.filter(item => !(item._type === 'planned' && item.id === routeId));
  applyFilters();
  showToast('Planned route deleted.', 'add');
}

// ========== GPX export for a planned route (already-snapped coords, no OSRM needed) ==========
function escapeGpx(str) {
  return String(str).replace(/[<>&"]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
}
function downloadPlannedRouteGPX(route) {
  if (!Array.isArray(route.route) || route.route.length < 2) {
    showToast('This route has no route data to export.', 'delete');
    return;
  }
  const title = route.title || 'Planned Route';
  const pts = route.route.map(c => `<rtept lat="${c[0]}" lon="${c[1]}"></rtept>`).join('\n        ');
  const gpxString = `<?xml version="1.0"?>
<gpx version="1.1" creator="Memory Lanes Ride Journal" xmlns="http://www.topografix.com/GPX/1/1">
  <rte>
    <name>${escapeGpx(title)}</name>
        ${pts}
  </rte>
</gpx>`;
  const blob = new Blob([gpxString], { type: 'application/gpx+xml' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${title.replace(/\s+/g, '_')}.gpx`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// ========== Status chip ==========
function statusChip(item) {
  if (item._type === 'planned') {
    return item.is_public
      ? '<span class="status-chip status-chip-planned">Planned</span> <span class="status-chip status-chip-shared">Shared</span>'
      : '<span class="status-chip status-chip-planned">Planned</span>';
  }
  if (item.is_public) return '<span class="status-chip status-chip-shared">Shared</span>';
  return '<span class="status-chip status-chip-completed">Completed</span>';
}

// ========== Rendering ==========
function renderItems(items) {
  rideList.innerHTML = '';
  if (!items.length) {
    rideList.textContent = 'Nothing here yet. Plan a route or upload a ride to get started.';
    return;
  }
  items.forEach(item => {
    rideList.appendChild(item._type === 'planned' ? renderPlannedCard(item) : renderRideCard(item));
  });
}

function renderPlannedCard(route) {
  const item = document.createElement('div');
  item.className = 'ride-entry planned-route-card';
  const created = route._date ? new Date(route._date).toLocaleDateString() : '';
  item.innerHTML = `
    <div class="ride-title-row">
      <div class="ride-title">
        ${escapeHtml(route.title)}
        ${statusChip(route)}
      </div>
      <div class="ride-meta">
        <span class="ride-date">${created}</span>
        <div class="delete-icon" title="Delete this route">${mlIconSVG('trash')}</div>
      </div>
    </div>
    <div class="ride-details">
      <span>${mlIconSVG('pin')} ${route.distance_km ? route.distance_km.toFixed(1) : '--'} km (est.)</span>
      <span>${mlIconSVG('mountain')} ${route.elevation_m != null ? Math.round(route.elevation_m) : '--'} m (est.)</span>
    </div>
    <div class="planner-route-actions">
      <button type="button" class="btn-primary planned-start-btn">${mlIconSVG('play')} Start Ride</button>
      <button type="button" class="btn-outline planned-edit-btn">${mlIconSVG('edit')} Edit</button>
      <button type="button" class="btn-outline planned-export-btn">${mlIconSVG('download')} Export</button>
      <button type="button" class="btn-outline planned-share-btn">${mlIconSVG('share')} ${route.is_public ? 'Copy Invite Link' : 'Invite a Rider'}</button>
      <button type="button" class="btn-outline planned-groupride-btn">${mlIconSVG('flag')} Group Ride</button>
    </div>
  `;
  item.querySelector('.planned-start-btn').addEventListener('click', (e) => {
    e.stopPropagation();
    window.location.href = `ride-live.html?route=${route.id}`;
  });
  item.querySelector('.planned-edit-btn').addEventListener('click', (e) => {
    e.stopPropagation();
    window.location.href = `planner.html?load=${route.id}`;
  });
  item.querySelector('.planned-export-btn').addEventListener('click', (e) => {
    e.stopPropagation();
    downloadPlannedRouteGPX(route);
  });
  item.querySelector('.planned-share-btn').addEventListener('click', async (e) => {
    e.stopPropagation();
    if (!route.is_public) {
      const { data, error } = await supabase
        .from('planned_routes')
        .update({ is_public: true })
        .eq('id', route.id)
        .select('is_public, share_token')
        .single();
      if (error) { showToast('Could not enable sharing.', 'delete'); return; }
      route.is_public = data.is_public;
      route.share_token = data.share_token;
    }
    const link = `${window.location.origin}${window.location.pathname.replace(/[^/]*$/, '')}route.html?share=${route.share_token}`;
    try {
      await navigator.clipboard.writeText(link);
      showToast('Invite link copied! Anyone with it can view and save this route.', 'add');
    } catch (_) {
      window.prompt('Copy this invite link:', link);
    }
    applyFilters(); // re-render (respecting active filters) so the Shared chip and button label update
  });
  item.querySelector('.planned-groupride-btn').addEventListener('click', async (e) => {
    e.stopPropagation();
    const title = window.prompt('Name this group ride:', `${route.title} — Group Ride`);
    if (title === null) return;
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { showToast('Please log in first.', 'info'); return; }
    const { data, error } = await supabase
      .from('group_rides')
      .insert({ route_id: route.id, owner_id: user.id, title: title.trim() || `${route.title} — Group Ride` })
      .select('share_token')
      .single();
    if (error) { showToast('Could not create the group ride.', 'delete'); return; }
    const link = `${window.location.origin}${window.location.pathname.replace(/[^/]*$/, '')}group.html?ride=${data.share_token}`;
    try { await navigator.clipboard.writeText(link); } catch (_) { window.prompt('Copy this group ride link:', link); }
    showToast('Group ride created — link copied! Opening the group page…', 'add');
    setTimeout(() => { window.location.href = link; }, 900);
  });
  item.querySelector('.delete-icon').addEventListener('click', (e) => {
    e.stopPropagation();
    deletePlannedRoute(route.id);
  });
  return item;
}

function renderRideCard(ride) {
  const item = document.createElement('div');
  item.className = 'ride-entry';
  const rideDate = ride._date ? new Date(ride._date).toLocaleDateString() : '';
  const overall = ride.skills?.scores
    ? Math.round(Object.values(ride.skills.scores).filter(Number.isFinite).reduce((a, b) => a + b, 0) /
        Math.max(1, Object.values(ride.skills.scores).filter(Number.isFinite).length))
    : null;

  item.innerHTML = `
    <div class="ride-title-row">
      <div class="ride-title">
        ${escapeHtml(ride.title)}
        ${Array.isArray(ride.moments) && ride.moments.length > 0
          ? `<span class="moments-icon" title="This ride has moments">${mlIconSVG('book')}</span>` : ''}
        ${statusChip(ride)}
      </div>
      <div class="ride-meta">
        <span class="ride-date">${rideDate}</span>
        <div class="delete-icon" title="Delete this ride" data-id="${ride.id}" data-path="${ride.gpx_path}">${mlIconSVG('trash')}</div>
      </div>
    </div>
    <div class="ride-details">
      <span>${mlIconSVG('pin')} ${ride.distance_km ? ride.distance_km.toFixed(1) : '--'} km</span>
      <span>⏱ ${ride.duration_min || '--'} min</span>
      <span>${mlIconSVG('mountain')} ${ride.elevation_m || '--'} m</span>
      ${overall != null ? `<span>${mlIconSVG('gauge')} Coach: ${overall}/100</span>` : ''}
    </div>
  `;

  item.addEventListener('click', (e) => {
    if (e.target.closest('.delete-icon')) return;
    window.location.href = `index.html?ride=${ride.id}`;
  });
  item.querySelector('.delete-icon').addEventListener('click', (e) => {
    e.stopPropagation();
    deleteRide(ride.id, ride.gpx_path);
  });
  return item;
}

// ========== Logout Button ==========
if (logoutBtn) {
  logoutBtn.addEventListener('click', async () => {
    await supabase.auth.signOut();
    window.location.href = 'index.html';
  });
}

// ========== New Ride Button ==========
if (newRideBtn) {
  newRideBtn.addEventListener('click', () => {
    window.location.href = 'index.html?home=1';
  });
}

// ========== Record a Ride Button ==========
const recordRideBtn = document.getElementById('record-ride-btn');
if (recordRideBtn) {
  recordRideBtn.addEventListener('click', () => {
    window.location.href = 'ride-live.html';
  });
}

// ========== Journal Button ==========
const journalBtn = document.getElementById('journal-btn');
if (journalBtn) {
  journalBtn.addEventListener('click', () => {
    window.location.href = 'journal.html';
  });
}

// ========== Stats Button ==========
const statsBtn = document.getElementById('stats-btn');
if (statsBtn) {
  statsBtn.addEventListener('click', () => {
    window.location.href = 'stats.html';
  });
}

// ========== Export All Data ==========
const exportBtn = document.getElementById('export-data-btn');
if (exportBtn) {
  exportBtn.addEventListener('click', async () => {
    if (exportBtn.disabled) return;
    if (typeof JSZip === 'undefined') {
      showToast('Export library failed to load. Check your connection and refresh.', 'delete');
      return;
    }
    exportBtn.disabled = true;
    const original = exportBtn.textContent;
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { showToast('Please log in first.', 'info'); return; }
      exportBtn.textContent = ' Preparing…';
      const { data: rows, error } = await supabase
        .from('ride_logs')
        .select('*')
        .eq('user_id', user.id)
        .order('ride_date', { ascending: false });
      if (error) throw error;
      const zip = new JSZip();
      zip.file('rides.json', JSON.stringify(rows, null, 2));
      zip.file('README.txt',
        'Memory Lanes data export\n\n' +
        'rides.json: every ride record, including titles, stats, moments, and Ride Coach skill summaries.\n' +
        'gpx/: the original GPX track for each ride.\n\n' +
        'Exported: ' + new Date().toISOString() + '\n');
      const withGpx = rows.filter(r => r.gpx_path);
      let done = 0, failed = 0;
      for (const ride of withGpx) {
        try {
          const { data: urlData } = supabase.storage.from('gpx-files').getPublicUrl(ride.gpx_path);
          const resp = await fetch(urlData.publicUrl);
          if (!resp.ok) throw new Error('HTTP ' + resp.status);
          const safe = (ride.title || 'ride').replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '_') || 'ride';
          zip.file(`gpx/${safe}_${String(ride.id).slice(0, 8)}.gpx`, await resp.blob());
        } catch (e) {
          failed++;
          console.warn('Export: GPX fetch failed for', ride.id, e);
        }
        done++;
        exportBtn.textContent = `Fetching GPX ${done}/${withGpx.length}`;
      }
      exportBtn.textContent = ' Zipping…';
      const blob = await zip.generateAsync({ type: 'blob' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `memory-lanes-export-${new Date().toISOString().slice(0, 10)}.zip`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(a.href), 5000);
      showToast(failed ? `Exported (${failed} GPX files could not be fetched).` : 'Export downloaded!', 'add');
    } catch (e) {
      console.error('Export failed:', e);
      showToast('Export failed: ' + (e.message || e), 'delete');
    } finally {
      exportBtn.disabled = false;
      exportBtn.textContent = original;
    }
  });
}

// ========== Toast Utility ==========
function showToast(msg, mode = "info") {
  let toast = document.createElement("div");
  toast.className = "custom-toast";
  toast.innerHTML = msg;
  toast.style.position = "fixed";
  toast.style.top = "50%";
  toast.style.left = "50%";
  toast.style.transform = "translate(-50%, -50%)";
  toast.style.background = mode === "delete" ? "#ff3333" : (mode === "add" ? "#21c821" : "#333");
  toast.style.color = "#fff";
  toast.style.padding = "0.8em 1.7em";
  toast.style.fontSize = "1.18rem";
  toast.style.borderRadius = "999px";
  toast.style.boxShadow = "0 3px 14px #0004";
  toast.style.zIndex = "99999";
  document.body.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = "0";
    setTimeout(() => { if (toast.parentNode) toast.parentNode.removeChild(toast); }, 450);
  }, 1200);
}


// ========== PWA: register the service worker ==========
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(err => console.warn('SW registration failed:', err));
  });
}
