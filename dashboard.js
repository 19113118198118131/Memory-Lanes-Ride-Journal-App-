// ===============================
// Memory Lanes Ride Journal - dashboard.js
// ===============================

// Supabase config
import supabase from './supabaseClient.js';

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
      <option value="distance_desc">Longest Ride</option>
      <option value="distance_asc">Shortest Ride</option>
      <option value="elevation_desc">Most Elevation</option>
      <option value="elevation_asc">Least Elevation</option>
    </select>
    <input type="text" id="searchInput" placeholder="🔍 Search title..." />
    <select id="monthFilter">
      <option value="">All Months</option>
    </select>
    <select id="yearFilter">
      <option value="">All Years</option>
    </select>
  </div>
`;
rideList.parentElement.insertBefore(filtersContainer, rideList);

let allRides = [];

// ========== Main initialization ==========
(async () => {
  // Get logged-in user, redirect to login if not authenticated
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    window.location.href = 'index.html';
    return;
  }

  // Fetch all rides for user, including moments
  const { data: rides, error: fetchError } = await supabase
    .from('ride_logs')
    .select('id, title, distance_km, duration_min, elevation_m, created_at, ride_date, gpx_path, moments')
    .eq('user_id', user.id)
    .order('ride_date', { ascending: false });

  if (fetchError) {
    showToast('Failed to load rides.', 'delete');
    rideList.textContent = 'Unable to load rides. Please try again.';
    return;
  }

  allRides = rides || [];

  populateMonthFilter(allRides);
  populateYearFilter(allRides);
  renderRides(allRides);

  // --- Attach filter and sort events ---
  document.getElementById('searchInput').addEventListener('input', applyFilters);
  document.getElementById('monthFilter').addEventListener('change', applyFilters);
  document.getElementById('yearFilter').addEventListener('change', applyFilters);
  document.getElementById('sort-select').addEventListener('change', applyFilters);
})();

// ========== Filtering & Sorting ==========
function applyFilters() {
  const keyword = document.getElementById('searchInput').value.toLowerCase();
  const month = document.getElementById('monthFilter').value;
  const year = document.getElementById('yearFilter').value;
  const sort = document.getElementById('sort-select').value;

  let filtered = allRides.filter(ride => {
    const matchesKeyword = ride.title.toLowerCase().includes(keyword);
    const rideDate = ride.ride_date ? new Date(ride.ride_date) : null;
    const matchesMonth = !month || (rideDate && rideDate.getMonth() === Number(month));
    const matchesYear = !year || (rideDate && rideDate.getFullYear().toString() === year);
    return matchesKeyword && matchesMonth && matchesYear;
  });

  // Sort filtered rides according to selected criteria
  switch (sort) {
    case 'date_asc':
      filtered.sort((a, b) => new Date(a.ride_date) - new Date(b.ride_date));
      break;
    case 'date_desc':
      filtered.sort((a, b) => new Date(b.ride_date) - new Date(a.ride_date));
      break;
    case 'distance_asc':
      filtered.sort((a, b) => a.distance_km - b.distance_km);
      break;
    case 'distance_desc':
      filtered.sort((a, b) => b.distance_km - a.distance_km);
      break;
    case 'elevation_asc':
      filtered.sort((a, b) => a.elevation_m - b.elevation_m);
      break;
    case 'elevation_desc':
      filtered.sort((a, b) => b.elevation_m - a.elevation_m);
      break;
  }

  renderRides(filtered);
}

// ========== Populate Month & Year Filter Dropdowns ==========
function populateMonthFilter(rides) {
  const monthFilter = document.getElementById('monthFilter');
  // Clear any old options except the default
  monthFilter.innerHTML = '<option value="">All Months</option>';
  const monthSet = new Set();
  rides.forEach(ride => {
    if (ride.ride_date) {
      const month = new Date(ride.ride_date).getMonth();
      monthSet.add(month);
    }
  });
  [...monthSet].sort((a, b) => a - b).forEach(m => {
    const opt = document.createElement('option');
    opt.value = m;
    opt.textContent = new Date(2025, m).toLocaleString('default', { month: 'long' });
    monthFilter.appendChild(opt);
  });
}

function populateYearFilter(rides) {
  const yearFilter = document.getElementById('yearFilter');
  // Clear any old options except the default
  yearFilter.innerHTML = '<option value="">All Years</option>';
  const yearSet = new Set();
  rides.forEach(ride => {
    if (ride.ride_date) {
      const year = new Date(ride.ride_date).getFullYear();
      yearSet.add(year);
    }
  });
  [...yearSet].sort((a, b) => a - b).forEach(y => {
    const opt = document.createElement('option');
    opt.value = y;
    opt.textContent = y;
    yearFilter.appendChild(opt);
  });
}

// ========== Ride Deletion ==========
async function deleteRide(rideId, gpxPath) {
  const confirmed = window.confirm('Are you sure you want to delete this ride? This cannot be undone.');
  if (!confirmed) return;

  // Delete from the ride_logs table
  const { error: deleteError } = await supabase
    .from('ride_logs')
    .delete()
    .eq('id', rideId);

  if (deleteError) {
    showToast(`❌ Failed to delete ride: ${deleteError.message}`, 'delete');
    return;
  }

  // Optional: Delete the GPX file from storage for cleanup
  if (gpxPath) {
    const { error: storageError } = await supabase
      .storage
      .from('gpx-files')
      .remove([gpxPath]);
    if (storageError) {
      // Warn but do not block UI if file deletion fails
      console.warn('⚠️ GPX file deletion failed:', storageError.message);
    }
  }

  // Update the list after deletion
  allRides = allRides.filter(r => r.id !== rideId);
  applyFilters(); // Re-render the filtered list
  showToast('✅ Ride deleted.', 'add');
}

// ========== Rides Rendering ==========
function renderRides(rides) {
  rideList.innerHTML = '';
  if (!rides.length) {
    rideList.textContent = 'No rides found.';
    return;
  }

  rides.forEach(ride => {
    const item = document.createElement('div');
    item.className = 'ride-entry';

    // Handle ride date
    const rideDate = ride.ride_date ? new Date(ride.ride_date).toLocaleDateString() : '';

    // Compose the ride entry HTML (Moments icon only if moments present)
    item.innerHTML = `
      <div class="ride-title-row">
        <div class="ride-title">
          ${ride.title}
          ${
            Array.isArray(ride.moments) && ride.moments.length > 0
              ? `<span class="moments-icon" title="This ride has moments!" style="margin-left:8px;font-size:1.2em;vertical-align:middle;">
                  <svg width="1.2em" height="1.2em" viewBox="0 0 24 24" fill="none" stroke="#8338ec" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="3" y="5" width="7" height="14" rx="2" fill="#fff" stroke="#8338ec"/>
                    <rect x="14" y="5" width="7" height="14" rx="2" fill="#fff" stroke="#8338ec"/>
                    <line x1="10" y1="8" x2="10" y2="16" stroke="#8338ec"/>
                  </svg>
                </span>`
              : ''
          }
        </div>
        <div class="ride-meta">
          <span class="ride-date">${rideDate}</span>
          <div class="delete-icon" title="Delete this ride" data-id="${ride.id}" data-path="${ride.gpx_path}">🗑️</div>
        </div>
      </div>
      <div class="ride-details">
        <span>📍 ${ride.distance_km ? ride.distance_km.toFixed(1) : '--'} km</span>
        <span>⏱ ${ride.duration_min || '--'} min</span>
        <span>⛰️ ${ride.elevation_m || '--'} m</span>
      </div>
    `;


    // Navigate to ride detail on click (except delete icon)
    item.addEventListener('click', (e) => {
      // Prevent navigation if clicking the delete icon
      if (e.target.classList.contains('delete-icon')) return;
      window.location.href = `index.html?ride=${ride.id}`;
    });

    // Attach delete event
    const deleteIcon = item.querySelector('.delete-icon');
    if (deleteIcon) {
      deleteIcon.addEventListener('click', (e) => {
        e.stopPropagation();
        deleteRide(ride.id, ride.gpx_path);
      });
    }

    rideList.appendChild(item);
  });
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

// ========== Journal Button ==========
const journalBtn = document.getElementById('journal-btn');
if (journalBtn) {
  journalBtn.addEventListener('click', () => {
    window.location.href = 'journal.html';
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
