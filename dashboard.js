// dashboard.js (complete version)
import supabase from './supabaseClient.js';

const rideList = document.getElementById('ride-list');
const logoutBtn = document.getElementById('logout-btn');
const homeBtn = document.getElementById('home-btn');

// 🔹 Add filter bar (search + month dropdown)
const filtersContainer = document.createElement('div');
filtersContainer.className = 'filters-container';
filtersContainer.innerHTML = `
  <input type="text" id="searchInput" placeholder="🔍 Search title..." />
  <select id="monthFilter">
    <option value="">All Months</option>
  </select>
`;
rideList.parentElement.insertBefore(filtersContainer, rideList);

let allRides = [];

(async () => {
  // 1. Check authentication
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    window.location.href = 'index.html';
    return;
  }

  // 2. Fetch rides
  const { data: rides, error: fetchError } = await supabase
    .from('ride_logs')
    .select('id, title, distance_km, duration_min, elevation_m, ride_date, gpx_path')
    .eq('user_id', user.id)
    .order('ride_date', { ascending: false });

  if (fetchError) {
    rideList.textContent = '❌ Failed to load rides.';
    return;
  }

  allRides = rides || [];
  populateMonthFilter(allRides);
  renderRides(allRides);

  // Hook up event listeners
  document.getElementById('searchInput').addEventListener('input', applyFilters);
  document.getElementById('monthFilter').addEventListener('change', applyFilters);
})();

function applyFilters() {
  const keyword = document.getElementById('searchInput').value.toLowerCase();
  const month = document.getElementById('monthFilter').value;
  const filtered = allRides.filter(ride => {
    const matchesKeyword = ride.title.toLowerCase().includes(keyword);
    const matchesMonth = !month || (ride.ride_date && new Date(ride.ride_date).getMonth().toString() === month);
    return matchesKeyword && matchesMonth;
  });
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
      alert(`Delete requested for ride ID: ${ride.id}`);
    });

    rideList.appendChild(item);
  });
}

// Navigation & logout
homeBtn.addEventListener('click', () => {
  window.location.href = 'index.html?home=1';
});

logoutBtn.addEventListener('click', async () => {
  await supabase.auth.signOut();
  window.location.href = 'index.html';
});
