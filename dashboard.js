// Supabase config
import supabase from './supabaseClient.js';

// DOM references
const rideList = document.getElementById('ride-list');
const logoutBtn = document.getElementById('logout-btn');
const newRideBtn = document.getElementById('home-btn');

// Filter UI container
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

// Main init
(async () => {
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    window.location.href = 'index.html';
    return;
  }

  const { data: rides, error: fetchError } = await supabase
    .from('ride_logs')
    .select('id, title, distance_km, duration_min, elevation_m, created_at, ride_date, gpx_path')
    .eq('user_id', user.id)
    .order('ride_date', { ascending: false });

  allRides = rides || [];

  populateMonthFilter(allRides);
  populateYearFilter(allRides);
  renderRides(allRides);

  document.getElementById('searchInput').addEventListener('input', applyFilters);
  document.getElementById('monthFilter').addEventListener('change', applyFilters);
  document.getElementById('yearFilter').addEventListener('change', applyFilters);
  document.getElementById('sort-select').addEventListener('change', applyFilters);
})();

function applyFilters() {
  const keyword = document.getElementById('searchInput').value.toLowerCase();
  const month = document.getElementById('monthFilter').value;
  const year = document.getElementById('yearFilter').value;
  const sort = document.getElementById('sort-select').value;

  let filtered = allRides.filter(ride => {
    const matchesKeyword = ride.title.toLowerCase().includes(keyword);
    const rideDate = new Date(ride.ride_date);
    const matchesMonth = !month || (rideDate.getMonth().toString() === month);
    const matchesYear = !year || (rideDate.getFullYear().toString() === year);
    return matchesKeyword && matchesMonth && matchesYear;
  });

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

function populateMonthFilter(rides) {
  const monthSet = new Set();
  rides.forEach(ride => {
    if (ride.ride_date) {
      const month = new Date(ride.ride_date).getMonth();
      monthSet.add(month);
    }
  });
  const monthFilter = document.getElementById('monthFilter');
  [...monthSet].sort().forEach(m => {
    const opt = document.createElement('option');
    opt.value = m;
    opt.textContent = new Date(2025, m).toLocaleString('default', { month: 'long' });
    monthFilter.appendChild(opt);
  });
}

function populateYearFilter(rides) {
  const yearSet = new Set();
  rides.forEach(ride => {
    if (ride.ride_date) {
      const year = new Date(ride.ride_date).getFullYear();
      yearSet.add(year);
    }
  });
  const yearFilter = document.getElementById('yearFilter');
  [...yearSet].sort().forEach(y => {
    const opt = document.createElement('option');
    opt.value = y;
    opt.textContent = y;
    yearFilter.appendChild(opt);
  });
}

async function deleteRide(rideId, gpxPath) {
  const confirmed = window.confirm('Are you sure you want to delete this ride? This cannot be undone.');
  if (!confirmed) return;

  // Delete from the ride_logs table
  const { error: deleteError } = await supabase
    .from('ride_logs')
    .delete()
    .eq('id', rideId);

  if (deleteError) {
    alert(`❌ Failed to delete ride: ${deleteError.message}`);
    return;
  }

  // Delete the GPX file from storage (optional cleanup)
  const { error: storageError } = await supabase
    .storage
    .from('gpx-files')
    .remove([gpxPath]);

  if (storageError) {
    console.warn('⚠️ GPX file deletion failed:', storageError.message);
  }

  // Update the list
  allRides = allRides.filter(r => r.id !== rideId);
  applyFilters(); // Re-render the filtered list
}


function renderRides(rides) {
  rideList.innerHTML = '';
  if (!rides.length) {
    rideList.textContent = 'No rides found.';
    return;
  }

  rides.forEach(ride => {
    const item = document.createElement('div');
    item.className = 'ride-entry';
    const rideDate = ride.ride_date ? new Date(ride.ride_date).toLocaleDateString() : '';
    item.innerHTML = `
      <div class="ride-title-row">
        <div class="ride-title">${ride.title}</div>
        <div class="ride-meta">
          <span class="ride-date">${rideDate}</span>
          <div class="delete-icon" title="Delete this ride" data-id="${ride.id}" data-path="${ride.gpx_path}">🗑️</div>
        </div>
      </div>
      <div class="ride-details">
        <span>📍 ${ride.distance_km.toFixed(1)} km</span>
        <span>⏱ ${ride.duration_min} min</span>
        <span>⛰️ ${ride.elevation_m} m</span>
      </div>
    `;
    item.addEventListener('click', () => {
      window.location.href = `index.html?ride=${ride.id}`;
    });

      const deleteIcon = item.querySelector('.delete-icon');
      deleteIcon.addEventListener('click', (e) => {
        e.stopPropagation();
        deleteRide(ride.id, ride.gpx_path);
      });


    rideList.appendChild(item);
  });
}

// Logout
logoutBtn.addEventListener('click', async () => {
  await supabase.auth.signOut();
  window.location.href = 'index.html';
});

newRideBtn.addEventListener('click', () => {
  window.location.href = 'index.html?home=1';
});
