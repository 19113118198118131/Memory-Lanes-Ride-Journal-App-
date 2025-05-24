import supabase from './supabaseClient.js';


const momentsList = document.getElementById('journal-moments-list');
const galleryBtn = document.getElementById('gallery-view-btn');
const timelineBtn = document.getElementById('timeline-view-btn');
const flipbookBtn = document.getElementById('flipbook-view-btn');
const roadTimelineContainer = document.getElementById('road-timeline-container');
const monthFilterContainer = document.getElementById('month-filter-container');
const rideFilterContainer = document.getElementById('ride-filter-container');
const flipbookContainer = document.getElementById('st-pageflip');
const flipStyleToggle = document.getElementById('flip-style-toggle');
const flipStyleSelect = document.getElementById('flip-style-select');

let pageFlipInstance = null; // Will hold the StPageFlip instance

// Utility: Error/Loading
function renderError(message) {
  if (momentsList) momentsList.innerHTML = `<div class="error-message">${message}</div>`;
  if (flipbookContainer) flipbookContainer.innerHTML = `<div class="error-message">${message}</div>`;
}
function renderLoading() {
  if (momentsList) momentsList.innerHTML = `<div class="loading-message">Loading your moments...</div>`;
}

// Core rendering: Moments as list/grid
function renderMoments(momentArr = []) {
  if (!momentsList) return;
  if (!Array.isArray(momentArr) || momentArr.length === 0) {
    momentsList.innerHTML = `<em>No moments found yet. Start adding moments on your rides!</em>`;
    return;
  }
  const frag = document.createDocumentFragment();
  momentArr.forEach(m => {
    const div = document.createElement('div');
    div.className = 'moment-entry journal-moment-card';
    div.innerHTML = `
      <div class="journal-moment-head">
        <strong>${m.title || 'Untitled Moment'}</strong>
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

// Timeline/Gallery/Flipbook View Toggle
function setupViewToggle({ onFlipbook, onList }) {
  if (!galleryBtn || !timelineBtn || !momentsList || !flipbookBtn) return;

  galleryBtn.addEventListener('click', () => {
    galleryBtn.classList.add('active');
    timelineBtn.classList.remove('active');
    flipbookBtn.classList.remove('active');
    momentsList.style.display = '';
    flipbookContainer.style.display = 'none';
    momentsList.classList.add('gallery-view');
    galleryBtn.setAttribute('aria-pressed', 'true');
    timelineBtn.setAttribute('aria-pressed', 'false');
    flipbookBtn.setAttribute('aria-pressed', 'false');
    if (flipStyleToggle) flipStyleToggle.style.display = 'none';
    if (onList) onList();
  });
  timelineBtn.addEventListener('click', () => {
    timelineBtn.classList.add('active');
    galleryBtn.classList.remove('active');
    flipbookBtn.classList.remove('active');
    momentsList.style.display = '';
    flipbookContainer.style.display = 'none';
    momentsList.classList.remove('gallery-view');
    timelineBtn.setAttribute('aria-pressed', 'true');
    galleryBtn.setAttribute('aria-pressed', 'false');
    flipbookBtn.setAttribute('aria-pressed', 'false');
    if (flipStyleToggle) flipStyleToggle.style.display = 'none';
    if (onList) onList();
  });
  flipbookBtn.addEventListener('click', () => {
    flipbookBtn.classList.add('active');
    galleryBtn.classList.remove('active');
    timelineBtn.classList.remove('active');
    momentsList.style.display = 'none';
    flipbookContainer.style.display = '';
    flipbookBtn.setAttribute('aria-pressed', 'true');
    galleryBtn.setAttribute('aria-pressed', 'false');
    timelineBtn.setAttribute('aria-pressed', 'false');
    if (flipStyleToggle) flipStyleToggle.style.display = '';
    if (onFlipbook) onFlipbook();
  });
}

// Road Timeline
function renderRoadTimeline(yearsArray, activeYear, onSelectYear) {
  if (!roadTimelineContainer) return;
  if (!Array.isArray(yearsArray) || yearsArray.length === 0) {
    roadTimelineContainer.innerHTML = '';
    return;
  }
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
      onSelectYear(year || null);
    });
  });
}

// Month Filter
function renderMonthFilter(monthsArray, activeMonth, onSelectMonth) {
  if (!monthFilterContainer) return;
  if (!Array.isArray(monthsArray) || monthsArray.length <= 1) {
    monthFilterContainer.innerHTML = '';
    return;
  }
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
  const select = document.getElementById('month-filter');
  if (select) {
    select.addEventListener('change', () => {
      onSelectMonth(select.value ? parseInt(select.value, 10) : null);
    });
  }
}

// Ride Filter
function renderRideFilter(ridesArray, activeRideId, onSelectRide) {
  if (!rideFilterContainer) return;
  if (!Array.isArray(ridesArray) || ridesArray.length <= 1) {
    rideFilterContainer.innerHTML = '';
    return;
  }
  let html = `<label for="ride-filter">Ride: </label>`;
  html += `<select id="ride-filter"><option value="">All Rides</option>`;
  ridesArray.forEach(r => {
    html += `<option value="${r.id}"${activeRideId === r.id ? ' selected' : ''}>${r.title || '(untitled ride)'}</option>`;
  });
  html += `</select>`;
  rideFilterContainer.innerHTML = html;
  const select = document.getElementById('ride-filter');
  if (select) {
    select.addEventListener('change', () => {
      onSelectRide(select.value || null);
    });
  }
}

// --- Magazine-Style Flipbook Rendering using StPageFlip ---
function renderStPageFlipBook(moments, animationStyle) {
  if (!flipbookContainer) return;
  flipbookContainer.style.display = '';
  if (momentsList) momentsList.style.display = 'none';

  // Destroy any previous flipbook instance
  if (pageFlipInstance) {
    pageFlipInstance.destroy();
    pageFlipInstance = null;
  }
  flipbookContainer.innerHTML = '';

  // If no moments, show message
  if (!Array.isArray(moments) || !moments.length) {
    flipbookContainer.innerHTML = `<em>No moments to display in flipbook.</em>`;
    return;
  }

  // Prepare HTML pages for the flipbook (each moment = 1 page)
  const pages = moments.map(m => `
    <div class="flipbook-card" style="background:none; box-shadow:none; margin:0; padding:0;">
      <div style="padding:2.2em 2em; border-radius:18px; background:linear-gradient(100deg, #1d2b43 70%, #132033 100%); box-shadow:0 6px 22px #1c2c4548;">
        <div class="journal-moment-head" style="font-size:1.14em;"><strong>${m.title || 'Untitled Moment'}</strong></div>
        <div class="journal-moment-meta" style="margin-top:0.5em;">${m.rideDate ? new Date(m.rideDate).toLocaleDateString() : ''} | <a href="index.html?ride=${m.rideId}" target="_blank">${m.rideTitle || '(untitled ride)'}</a></div>
        <div class="journal-moment-note" style="margin-top:1em;">${m.note ? m.note : '<em>(No notes)</em>'}</div>
        <div style="margin-top:2em; font-size:0.9em; color:#99e; text-align:right;">${typeof m.speed === 'number' ? `Speed: ${m.speed.toFixed(1)} km/h` : ''} ${typeof m.elevation === 'number' ? `&bull; Elev: ${m.elevation.toFixed(0)} m` : ''}</div>
      </div>
    </div>
  `);

  // Instantiate StPageFlip using the *global* object!
  pageFlipInstance = new window.PageFlip(flipbookContainer, {
    width: 480,
    height: 320,
    size: "fixed",
    minWidth: 320,
    maxWidth: 780,
    minHeight: 200,
    maxHeight: 900,
    maxShadowOpacity: 0.32,
    showCover: false,
    mobileScrollSupport: true,
    usePortrait: false,
    swipeDistance: 25,
    disableFlipByClick: false,
    startPage: 0,
    drawShadow: true,
    flippingTime: animationStyle === 'flip' ? 700 : 380,
    startZIndex: 1,
  });

  // Load pages
  pageFlipInstance.loadFromHTML(pages);

  // Optional: Keyboard navigation
  document.onkeydown = (e) => {
    if (flipbookContainer.style.display === 'none') return;
    if (!pageFlipInstance) return;
    if (e.key === "ArrowLeft") pageFlipInstance.flipPrev();
    else if (e.key === "ArrowRight") pageFlipInstance.flipNext();
  };
}

// ========== Main app logic ==========
let flipbookFiltered = [], flipbookAnim = 'slide';

(async function main() {
  renderLoading();

  // Authenticate
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

  // Fetch rides and handle errors
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

  // Flatten all moments, add ride info, filter bad/empty moments
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

  // Sort by ride date (desc), then by moment idx (desc)
  allMoments.sort((a, b) => {
    const dateA = new Date(a.rideDate);
    const dateB = new Date(b.rideDate);
    if (dateA - dateB !== 0) return dateB - dateA;
    return (b.idx || 0) - (a.idx || 0);
  });

  // Derive years
  const years = Array.from(new Set(
    allMoments
      .map(m => (m.rideDate ? new Date(m.rideDate).getFullYear() : null))
      .filter(Boolean)
  )).sort((a, b) => a - b);

  // ========== State ==========
  let selectedYear = null, selectedMonth = null, selectedRide = null;

  // Helpers
  function filterMoments(year, month, rideId) {
    return allMoments.filter(m => {
      if (!m.rideDate) return false;
      const d = new Date(m.rideDate);
      const y = d.getFullYear();
      const mth = d.getMonth() + 1;
      return (!year || y === parseInt(year, 10)) &&
             (!month || mth === parseInt(month, 10)) &&
             (!rideId || m.rideId === rideId);
    });
  }
  function getMonthsForYear(year) {
    return Array.from(new Set(
      allMoments
        .filter(m => m.rideDate && new Date(m.rideDate).getFullYear() === parseInt(year, 10))
        .map(m => new Date(m.rideDate).getMonth() + 1)
    )).sort((a, b) => a - b);
  }
  function getRidesForYearMonth(year, month) {
    // Rides that have at least one moment in that year+month
    const rideMap = new Map();
    allMoments.forEach(m => {
      if (!m.rideDate) return;
      const d = new Date(m.rideDate);
      const y = d.getFullYear();
      const mth = d.getMonth() + 1;
      if ((!year || y === parseInt(year, 10)) && (!month || mth === parseInt(month, 10))) {
        if (!rideMap.has(m.rideId)) rideMap.set(m.rideId, { id: m.rideId, title: m.rideTitle });
      }
    });
    return Array.from(rideMap.values()).sort((a, b) => (a.title || '').localeCompare(b.title || ''));
  }

  // Filter and update controls, and render
  function updateFiltersAndRender(renderFlip = false) {
    renderRoadTimeline(years, selectedYear, handleYearSelect);
    const months = selectedYear ? getMonthsForYear(selectedYear) : [];
    renderMonthFilter(months, selectedMonth, handleMonthSelect);
    const ridesForFilters = getRidesForYearMonth(selectedYear, selectedMonth);
    renderRideFilter(ridesForFilters, selectedRide, handleRideSelect);
    const filtered = filterMoments(selectedYear, selectedMonth, selectedRide);
    flipbookFiltered = filtered;
    // List/grid or flipbook?
    if (flipbookBtn.classList.contains('active')) {
      renderStPageFlipBook(filtered, flipbookAnim);
    } else {
      if (pageFlipInstance) { pageFlipInstance.destroy(); pageFlipInstance = null; }
      flipbookContainer.style.display = 'none';
      momentsList.style.display = '';
      renderMoments(filtered);
    }
  }

  // --- Filter handlers ---
  function handleYearSelect(year) {
    selectedYear = year;
    selectedMonth = null;
    selectedRide = null;
    updateFiltersAndRender(true);
  }
  function handleMonthSelect(month) {
    selectedMonth = month;
    selectedRide = null;
    updateFiltersAndRender(true);
  }
  function handleRideSelect(rideId) {
    selectedRide = rideId;
    updateFiltersAndRender(true);
  }

  // --- Flipbook animation style ---
  if (flipStyleSelect) {
    flipStyleSelect.addEventListener('change', () => {
      flipbookAnim = flipStyleSelect.value;
      if (flipbookBtn.classList.contains('active')) {
        renderStPageFlipBook(flipbookFiltered, flipbookAnim);
      }
    });
  }

  // --- Setup all view toggles ---
  setupViewToggle({
    onFlipbook: () => {
      updateFiltersAndRender(true);
      if (flipStyleToggle) flipStyleToggle.style.display = '';
    },
    onList: () => {
      updateFiltersAndRender();
      if (flipStyleToggle) flipStyleToggle.style.display = 'none';
    }
  });

  // --- Initial render ---
  renderRoadTimeline(years, selectedYear, handleYearSelect);
  renderMoments(allMoments);

  // Default to Timeline view on load
  if (timelineBtn) timelineBtn.classList.add('active');
  if (flipStyleToggle) flipStyleToggle.style.display = 'none';
})();
