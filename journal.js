import supabase from './supabaseClient.js';

const momentsList = document.getElementById('journal-moments-list');
const galleryBtn = document.getElementById('gallery-view-btn');
const timelineBtn = document.getElementById('timeline-view-btn');
const roadTimelineContainer = document.getElementById('road-timeline-container');
const monthFilterContainer = document.getElementById('month-filter-container');

// === Utility Functions ===

// Render an error message to the moments area
function renderError(message) {
  if (momentsList) {
    momentsList.innerHTML = `<div class="error-message">${message}</div>`;
  }
}

// Render a loading state
function renderLoading() {
  if (momentsList) {
    momentsList.innerHTML = `<div class="loading-message">Loading your moments...</div>`;
  }
}

// Render moments (accepts array of moment objects)
function renderMoments(momentArr = []) {
  if (!momentsList) return;

  if (!Array.isArray(momentArr) || momentArr.length === 0) {
    momentsList.innerHTML = `<em>No moments found yet. Start adding moments on your rides!</em>`;
    return;
  }

  // Use document fragment for performance with large lists
  const frag = document.createDocumentFragment();

  momentArr.forEach(m => {
    const div = document.createElement('div');
    div.className = 'moment-entry journal-moment-card';
    div.innerHTML = `
      <div class="journal-moment-head">
        <strong>${m.title ? m.title : 'Untitled Moment'}</strong>
        <span style="color:#64ffda;margin-left:1em;">${m.rideDate ? new Date(m.rideDate).toLocaleDateString() : ''}</span>
      </div>
      <div class="journal-moment-meta">
        <span>From <a href="index.html?ride=${m.rideId}" style="color:#00c6ff;text-decoration:underline;">${m.rideTitle || '(untitled ride)'}</a></span>
        ${typeof m.speed === 'number' ? `<span>• ${m.speed.toFixed(1)} km/h</span>` : ''}
        ${typeof m.elevation === 'number' ? `<span>• ${m.elevation.toFixed(0)} m</span>` : ''}
      </div>
      <div class="journal-moment-note">${m.note ? m.note : '<em>(No notes)</em>'}</div>
    `;
    frag.appendChild(div);
  });

  momentsList.innerHTML = '';
  momentsList.appendChild(frag);
}

// Setup Timeline/Gallery View Toggle
function setupViewToggle() {
  if (!galleryBtn || !timelineBtn || !momentsList) return;
  galleryBtn.addEventListener('click', () => {
    galleryBtn.classList.add('active');
    timelineBtn.classList.remove('active');
    momentsList.classList.add('gallery-view');
    galleryBtn.setAttribute('aria-pressed', 'true');
    timelineBtn.setAttribute('aria-pressed', 'false');
  });
  timelineBtn.addEventListener('click', () => {
    timelineBtn.classList.add('active');
    galleryBtn.classList.remove('active');
    momentsList.classList.remove('gallery-view');
    timelineBtn.setAttribute('aria-pressed', 'true');
    galleryBtn.setAttribute('aria-pressed', 'false');
  });
}

// Render the horizontal "road" timeline by year and attach click events
function renderRoadTimeline(yearsArray, activeYear, onSelectYear) {
  if (!roadTimelineContainer) return;
  if (!Array.isArray(yearsArray) || yearsArray.length === 0) {
    roadTimelineContainer.innerHTML = '';
    return;
  }

  // Horizontal scrollable timeline styled as a road
  let html = `<div class="road-timeline">`;
  html += `<button class="road-marker${!activeYear ? ' active' : ''}" data-year="" title="Show all years">🏁</button>`;
  yearsArray.forEach(year => {
    html += `<button class="road-marker${activeYear === year ? ' active' : ''}" data-year="${year}" title="Show ${year}">${year}</button>`;
  });
  html += `</div>`;
  roadTimelineContainer.innerHTML = html;

  roadTimelineContainer.querySelectorAll('.road-marker').forEach(marker => {
    marker.addEventListener('click', () => {
      const year = marker.getAttribute('data-year');
      onSelectYear(year || null); // Pass null for "Show All"
    });
  });
}

// Render a month filter dropdown (based on filtered moments)
function renderMonthFilter(monthsArray, activeMonth, onSelectMonth) {
  if (!monthFilterContainer) return;

  // No months to filter (or only one) = hide dropdown
  if (!Array.isArray(monthsArray) || monthsArray.length <= 1) {
    monthFilterContainer.innerHTML = '';
    return;
  }

  // Month names
  const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  let html = `<label for="month-filter">Month: </label>`;
  html += `<select id="month-filter"><option value="">All Months</option>`;
  monthsArray.forEach(m => {
    html += `<option value="${m}"${activeMonth === m ? ' selected' : ''}>${monthNames[m - 1]}</option>`;
  });
  html += `</select>`;
  monthFilterContainer.innerHTML = html;

  // Attach event
  const select = document.getElementById('month-filter');
  if (select) {
    select.addEventListener('change', () => {
      onSelectMonth(select.value ? parseInt(select.value, 10) : null);
    });
  }
}

// ========== Main app logic ==========
(async function main() {
  renderLoading();

  // 1. Authenticate user
  let user;
  try {
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData || !authData.user) {
      renderError('Please log in to view your Rider’s Journal.');
      return;
    }
    user = authData.user;
  } catch (e) {
    renderError('Unexpected authentication error. Please reload.');
    return;
  }

  // 2. Fetch rides and handle errors
  let rides;
  try {
    const { data, error } = await supabase
      .from('ride_logs')
      .select('id, title, ride_date, moments')
      .eq('user_id', user.id)
      .order('ride_date', { ascending: false });

    if (error || !Array.isArray(data)) {
      renderError('Failed to load your moments. Please try again later.');
      return;
    }
    rides = data;
  } catch (e) {
    renderError('Error fetching rides. Please check your network and try again.');
    return;
  }

  // 3. Flatten all moments, add ride info, filter bad/empty moments
  const allMoments = [];
  rides.forEach(ride => {
    if (Array.isArray(ride.moments)) {
      ride.moments.forEach((moment, idx) => {
        if (moment && typeof moment === 'object') {
          allMoments.push({
            ...moment,
            rideId: ride.id,
            rideTitle: ride.title,
            rideDate: ride.ride_date,
            idx: idx
          });
        }
      });
    }
  });

  // 4. Sort by ride date (desc), then by moment idx (desc)
  allMoments.sort((a, b) => {
    const dateA = new Date(a.rideDate);
    const dateB = new Date(b.rideDate);
    if (dateA - dateB !== 0) return dateB - dateA;
    return (b.idx || 0) - (a.idx || 0);
  });

  // 5. Derive years
  const years = Array.from(new Set(
    allMoments
      .map(m => (m.rideDate ? new Date(m.rideDate).getFullYear() : null))
      .filter(Boolean)
  )).sort((a, b) => a - b);

  // ========== State ==========
  let selectedYear = null;
  let selectedMonth = null;

  // Helper: filter moments by year and month
  function filterMoments(year, month) {
    return allMoments.filter(m => {
      if (!m.rideDate) return false;
      const d = new Date(m.rideDate);
      const y = d.getFullYear();
      const mth = d.getMonth() + 1;
      return (!year || y === parseInt(year, 10)) &&
             (!month || mth === parseInt(month, 10));
    });
  }

  // Helper: get all months (as numbers) for a given year in the data
  function getMonthsForYear(year) {
    return Array.from(new Set(
      allMoments
        .filter(m => m.rideDate && new Date(m.rideDate).getFullYear() === parseInt(year, 10))
        .map(m => new Date(m.rideDate).getMonth() + 1)
    )).sort((a, b) => a - b);
  }

  // Handler: when timeline marker is clicked
  function handleYearSelect(year) {
    selectedYear = year;
    selectedMonth = null;
    renderRoadTimeline(years, selectedYear, handleYearSelect);
    // If year is selected, render month filter if >1 month in data
    if (selectedYear) {
      const months = getMonthsForYear(selectedYear);
      renderMonthFilter(months, selectedMonth, handleMonthSelect);
      renderMoments(filterMoments(selectedYear, null));
    } else {
      monthFilterContainer.innerHTML = '';
      renderMoments(allMoments);
    }
  }

  // Handler: when month is selected
  function handleMonthSelect(month) {
    selectedMonth = month;
    renderMonthFilter(getMonthsForYear(selectedYear), selectedMonth, handleMonthSelect);
    renderMoments(filterMoments(selectedYear, selectedMonth));
  }

  // ========== Initial render ==========
  renderRoadTimeline(years, selectedYear, handleYearSelect);
  renderMoments(allMoments);
  setupViewToggle();

  // Optionally: Add future hooks for advanced filters/search here
})();
