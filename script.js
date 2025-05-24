// =============================================
// Memory Lanes Ride Journal - script.js
// =============================================

import supabase from './supabaseClient.js';

document.addEventListener('DOMContentLoaded', async () => {
  // =====================================================
  // SECTION 1: UI ELEMENT REFERENCES & UI STATE HELPERS
  // =====================================================
  
  // Helper: Fade in any element with smooth transition
    function fadeInElement(el) {
      el.classList.remove('fade-in'); // reset in case it's already applied
      void el.offsetWidth;            // force reflow
      el.classList.add('fade-in');
    }
  
  const uploadSection     = document.getElementById('upload-section');
  const saveForm          = document.getElementById('save-ride-form');
  const authSection       = document.getElementById('auth-section');
  const mainRideUI        = document.getElementById('main-ride-ui');
  const analyticsSection  = document.getElementById('analytics-container');
  const showAnalyticsBtn  = document.getElementById('show-analytics-btn');
  const downloadSummary   = document.getElementById('download-summary');
  const exportVideo       = document.getElementById('export-video');
  const rideActions       = document.getElementById('ride-actions');
  const editControls      = document.getElementById('edit-controls');
  const editExperimentalBanner = document.getElementById('edit-experimental-banner');
  const editBtn           = document.getElementById('edit-gpx-btn');
  const saveEditBtn       = document.getElementById('save-edited-gpx-btn');
  const undoEditBtn       = document.getElementById('undo-edit-btn');
  const redoEditBtn       = document.getElementById('redo-edit-btn');
  const bulkAddBtn        = document.getElementById('bulk-add-btn');
  const bulkDeleteBtn     = document.getElementById('bulk-delete-btn');
  const exitEditBtn       = document.getElementById('exit-edit-btn');
  const editHelp          = document.getElementById('edit-help');
  const editModeHint      = document.getElementById('edit-mode-hint');
  const momentsSection   = document.getElementById('moments-section');
  const toggleMomentsBtn = document.getElementById('toggle-moments');
  const momentsTools     = document.getElementById('moments-tools');
  const addMomentBtn     = document.getElementById('add-moment-btn');
  const momentsList      = document.getElementById('moments-list'); 
  let rideMoments        = []; // Local array to store moments for current ride
  

  
function renderMoments() {
  momentsList.innerHTML = '';
  if (!rideMoments.length) {
    momentsList.innerHTML = '<em>No moments saved yet. Click "Add Moment" while replaying your ride to save your favorite spot or note.</em>';
    addMomentBtn.disabled = false;
    return;
  }
  addMomentBtn.disabled = rideMoments.length >= 5;
  rideMoments.forEach((m, i) => {
    const div = document.createElement('div');
    div.className = 'moment-entry';
    div.innerHTML = `
      <div style="display: flex; gap: 1rem; align-items: center; margin-bottom: 0.3rem;">
        <span style="font-size:1.15em;">📍</span>
        <span>
          <strong>Km:</strong> ${(cumulativeDistance[m.idx]/1000).toFixed(2) || '--'}<br>
          <strong>Speed:</strong> ${m.speed?.toFixed(1) || '--'} km/h<br>
          <strong>Elevation:</strong> ${m.elevation?.toFixed(0) || '--'} m
        </span>
        <button class="jump-moment-btn btn-muted" data-idx="${i}" style="margin-left:auto;">Jump</button>
        <button class="delete-moment-btn btn-muted" data-idx="${i}" style="margin-left:0.8rem;color:#ff6b6b;">🗑️</button>
      </div>
      <input type="text" placeholder="Moment title (optional)" value="${m.title || ''}" class="moment-title-input" data-idx="${i}" style="width: 90%; margin-bottom: 0.3rem;" />
      <textarea placeholder="Your notes or memory..." class="moment-note-input" data-idx="${i}" style="width: 90%; min-height: 48px;">${m.note || ''}</textarea>
      <hr style="border:0; border-top:1px solid #223; margin: 0.7rem 0;">
    `;
    momentsList.appendChild(div);
  });

  // Add jump and delete logic
  momentsList.querySelectorAll('.jump-moment-btn').forEach(btn => {
    btn.addEventListener('click', e => {
      const idx = +btn.dataset.idx;
      if (rideMoments[idx]) {
        window.jumpToPlaybackIndex(rideMoments[idx].idx);
      }
    });
  });

  momentsList.querySelectorAll('.delete-moment-btn').forEach(btn => {
    btn.addEventListener('click', e => {
      const idx = +btn.dataset.idx;
      if (confirm('Delete this moment?')) {
        rideMoments.splice(idx, 1);
        saveMomentsToDB();
        renderMoments();
      }
    });
  });

  // Add edit logic (auto-save on blur)
  momentsList.querySelectorAll('.moment-title-input').forEach(input => {
    input.addEventListener('change', e => {
      const idx = +input.dataset.idx;
      rideMoments[idx].title = input.value;
      saveMomentsToDB();
    });
  });

  momentsList.querySelectorAll('.moment-note-input').forEach(textarea => {
    textarea.addEventListener('change', e => {
      const idx = +textarea.dataset.idx;
      rideMoments[idx].note = textarea.value;
      saveMomentsToDB();
    });
  });


// --- Add/refresh map markers for moments ---
if (window.momentsMarkers) {
  window.momentsMarkers.forEach(m => map.removeLayer(m));
}
window.momentsMarkers = [];
rideMoments.forEach((m, i) => {
  if (typeof m.lat === "number" && typeof m.lng === "number") {
    const marker = L.marker([m.lat, m.lng], {
      icon: L.divIcon({ className: 'moment-pin', html: `<span style="color:#8338ec;font-size:1.4em;">★</span>` })
    }).addTo(map);
    marker.on('click', () => {
      window.jumpToPlaybackIndex(m.idx);
    });
    window.momentsMarkers.push(marker);
  }
});

}


async function saveMomentsToDB() {
  const params = new URLSearchParams(window.location.search);
  const rideId = params.get('ride');
  const { error } = await supabase
    .from('ride_logs')
    .update({ moments: rideMoments })
    .eq('id', rideId);
  if (error) showToast('Failed to save moments', 'delete');
}

  
  // ----- UI visibility logic -----
  function resetUIToInitial() {
    uploadSection.style.display        = 'block';
    saveForm.style.display             = 'none';
    authSection.style.display          = 'none';
    mainRideUI.style.display           = 'none';
    analyticsSection.style.display     = 'none';
    showAnalyticsBtn.style.display     = 'none';
    downloadSummary.style.display      = 'none';
    exportVideo.style.display          = 'none';
    rideActions.style.display          = 'none';
    editControls.style.display         = 'none';
    editHelp.style.display             = 'none';
    document.getElementById('gpx-upload').value = '';
  }

  function showUIAfterUpload(isLoggedIn) {
    uploadSection.style.display        = 'block';
    mainRideUI.style.display           = 'block';
    saveForm.style.display             = 'block';
    showAnalyticsBtn.style.display     = 'inline-block';
    analyticsSection.style.display     = 'none';
    downloadSummary.style.display      = 'inline-block';
    exportVideo.style.display          = 'inline-block';
    rideActions.style.display          = 'none';
    authSection.style.display          = isLoggedIn ? 'none' : 'block';
    setTimeout(() => map.invalidateSize(), 200);
    editControls.style.display         = 'flex';
  }

  function showUIForSavedRide() {
    uploadSection.style.display        = 'none';
    mainRideUI.style.display           = 'block';
    saveForm.style.display             = 'none';
    authSection.style.display          = 'none';
    showAnalyticsBtn.style.display     = 'inline-block';
    analyticsSection.style.display     = 'none';
    downloadSummary.style.display      = 'inline-block';
    exportVideo.style.display          = 'inline-block';
    rideActions.style.display          = 'flex';
    setTimeout(() => map.invalidateSize(), 200);
    editControls.style.display         = 'flex';
  }

  function showAnalyticsSection() {
    analyticsSection.style.display     = 'block';
    showAnalyticsBtn.style.display     = 'none';
    analyticsSection.scrollIntoView({ behavior: 'smooth' });
  }

  function hideAnalyticsSection() {
    analyticsSection.style.display     = 'none';
    showAnalyticsBtn.style.display     = 'inline-block';
  }

  // =====================================================
  // SECTION 2: RIDE DATA & STATE
  // =====================================================
  const FRAME_DELAY_MS    = 50;
  const slider            = document.getElementById('replay-slider');
  const playBtn           = document.getElementById('play-replay');
  const summaryBtn        = document.getElementById('download-summary');
  const videoBtn          = document.getElementById('export-video');
  const speedSel          = document.getElementById('playback-speed');
  const distanceEl        = document.getElementById('distance');
  const durationEl        = document.getElementById('duration');
  const rideTimeEl        = document.getElementById('ride-time');
  const elevationEl       = document.getElementById('elevation');
  const saveBtn           = document.getElementById('save-ride-btn');
  const rideTitleDisplay  = document.getElementById('ride-title-display');
  const uploadAnotherBtn  = document.getElementById('upload-another');
  const showSaveForm      = () => saveForm.style.display = 'block';
  const hideSaveForm      = () => saveForm.style.display = 'none';
  const uploadInput = document.getElementById('gpx-upload');
  const fileStatus = document.getElementById('file-upload-status');
  const postUploadActions = document.getElementById('post-upload-actions');

uploadInput.addEventListener('change', () => {
  const file = uploadInput.files[0];
  if (file) {
    fileStatus.textContent = '✔️ File ready';
    fileStatus.classList.add('ready');
    postUploadActions.style.display = 'flex';
  } else {
    fileStatus.textContent = 'No file selected';
    fileStatus.classList.remove('ready');
    postUploadActions.style.display = 'none';
    document.getElementById('gpx-upload').value = '';
  }
});
     
  
  let points = [], marker = null, trailPolyline = null, elevationChart = null;
  let cumulativeDistance = [], speedData = [], breakPoints = [], accelData = [];
  window.playInterval = null;
  window.fracIndex = 0;
  window.updatePlayback = null;
  let speedHighlightLayer = null;
  let selectedSpeedBins = new Set();

  const speedBins = [
    { label: '50–80', min: 50, max: 80 },
    { label: '80–100', min: 80, max: 100 },
    { label: '100–120', min: 100, max: 120 },
    { label: '120–160', min: 120, max: 160 },
    { label: '160–200', min: 160, max: 200 },
    { label: '200+', min: 200, max: Infinity }
  ];


  // =====================================================
  // SECTION 3: GPX PARSER & MAP RENDERING
  // =====================================================
  function parseAndRenderGPX(gpxText) {
    const xml = new DOMParser().parseFromString(gpxText, 'application/xml');
    const trkpts = Array.from(xml.getElementsByTagName('trkpt')).map(tp => ({
      lat: +tp.getAttribute('lat'),
      lng: +tp.getAttribute('lon'),
      ele: +tp.getElementsByTagName('ele')[0]?.textContent || 0,
      time: new Date(tp.getElementsByTagName('time')[0]?.textContent)
    })).filter(p => p.lat && p.lng && p.time instanceof Date);

    if (!trkpts.length) return alert('No valid trackpoints found');

    // Downsample, breakpoints
    const SAMPLE = 5;
    points = [trkpts[0]];
    breakPoints = [];
    let lastTime = trkpts[0].time;
    let lastLL   = L.latLng(trkpts[0].lat, trkpts[0].lng);

    for (let i = 1; i < trkpts.length; i++) {
      const pt    = trkpts[i];
      const dt    = (pt.time - lastTime) / 1000;
      const moved = lastLL.distanceTo(L.latLng(pt.lat, pt.lng));
      if (dt >= SAMPLE) {
        if (dt > 180 && moved < 20) {
          breakPoints.push(points.length);
        } else {
          points.push(pt);
          lastTime = pt.time;
          lastLL   = L.latLng(pt.lat, pt.lng);
        }
      }
    }
    if (points.at(-1).time !== trkpts.at(-1).time) {
      points.push(trkpts.at(-1));
    }

    // Distance/speed/accel
    cumulativeDistance = [0];
    speedData          = [0];
    accelData          = [0];
    for (let i = 1; i < points.length; i++) {
      const a = L.latLng(points[i-1].lat, points[i-1].lng);
      const b = L.latLng(points[i].lat,   points[i].lng);
      const d = a.distanceTo(b); // meters
      const t = (points[i].time - points[i-1].time) / 1000; // seconds
      const v = t > 0 ? d / t : 0; // m/s
      cumulativeDistance[i] = cumulativeDistance[i-1] + d;
      speedData[i]          = v * 3.6;
      accelData[i]          = t > 0 ? (v - (speedData[i-1] / 3.6)) / t : 0;
    }

    // Update summary UI
    const totalMs = points.at(-1).time - points[0].time;
    const totMin  = Math.floor(totalMs / 60000);
    distanceEl.textContent = `${(cumulativeDistance.at(-1) / 1000).toFixed(2)} km`;
    durationEl.textContent = `${Math.floor(totMin / 60)}h ${totMin % 60}m`;
    const rideSec = points.reduce((sum, _, i) =>
      i > 0 && !breakPoints.includes(i)
        ? sum + ((points[i].time - points[i-1].time) / 1000)
        : sum, 0);
    const rideMin = Math.floor(rideSec / 60);
    rideTimeEl.textContent   = `${Math.floor(rideMin / 60)}h ${rideMin % 60}m`;
    elevationEl.textContent  = `${points.reduce((sum, p, i) =>
      i>0 && p.ele>points[i-1].ele ? sum + (p.ele - points[i-1].ele) : sum, 0).toFixed(0)} m`;

    // Draw route
    if (trailPolyline) map.removeLayer(trailPolyline);
    trailPolyline = L.polyline(points.map(p => [p.lat, p.lng]), {
      color: '#007bff', weight: 3, opacity: 0.7
    }).addTo(map).bringToBack();

    setTimeout(() => {
      map.invalidateSize();
      if (trailPolyline && points.length > 1) {
        map.fitBounds(trailPolyline.getBounds(), { padding: [30,30], animate: true });
      } else if (points.length === 1) {
        map.setView([points[0].lat, points[0].lng], 13);
      }
    }, 210);

    setupChart();
    renderSpeedFilter();
    renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
    [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = false);
    slider.min = 0; slider.max = points.length - 1; slider.value = 0;
    playBtn.textContent = '▶️ Play';

    if (window.Analytics) {
      Analytics.initAnalytics(points, speedData, cumulativeDistance);
      renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
    }

    hideAnalyticsSection();
    showAnalyticsBtn.style.display = 'inline-block';
  }

  // =====================================================
  // SECTION 4: LEAFLET MAP SETUP
  // =====================================================
  const map = L.map('leaflet-map').setView([20, 0], 2);
  map.editTools = new L.Editable(map); // Enable editing support!
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);
  setTimeout(() => map.invalidateSize(), 0);

// =======================
// EDIT MODE (Improved & Robust Multi-Segment Handling)
// =======================

// --- Edit Mode State ---
let isEditing = false;
let editablePolyline = null;
let editHistory = [];
let redoHistory = [];
let bulkMode = null; // "add", "delete", or null
let brushPath = [];
let brushLayer = null;
let originalPoints = [];
let ghostAddLine = null;
let highlightedDeleteMarkers = [];
let lastBrushMove = 0;

// --- Utility: Visual feedback cleanup ---
function clearGhostsAndHighlights() {
  if (brushLayer) { map.removeLayer(brushLayer); brushLayer = null; }
  if (ghostAddLine) { map.removeLayer(ghostAddLine); ghostAddLine = null; }
  highlightedDeleteMarkers.forEach(m => map.removeLayer(m));
  highlightedDeleteMarkers = [];
}

// --- Toggle Bulk Mode ---
function setBulkMode(mode) {
  bulkMode = mode;
  bulkAddBtn.classList.toggle('active', mode === 'add');
  bulkDeleteBtn.classList.toggle('active', mode === 'delete');
  editModeHint.innerHTML = mode === 'add'
    ? 'Bulk Add: Draw a new section (green) to append to route. Map will not pan.'
    : mode === 'delete'
      ? 'Bulk Delete: Draw (red) over points to erase them. Map will not pan or drag points.'
      : '';
  // Disable all Leaflet dragging during bulk tools!
  if (mode) {
    map.dragging.disable();
    if (editablePolyline && editablePolyline.editor) {
      editablePolyline.editor.disable();
    }
  } else {
    map.dragging.enable();
    if (editablePolyline && editablePolyline.editor) {
      editablePolyline.editor.enable();
    }
  }
  clearGhostsAndHighlights();
}

// --- ENTER EDIT MODE ---
editBtn.onclick = function() {
  if (isEditing) return;
  // --- Show experimental feature banner ---
  editExperimentalBanner.style.display = 'block'; // Use block for div, '' can inherit or be ignored
  editExperimentalBanner.innerHTML = `
    <span style="
      color:#fff; background:#b48d07; padding:7px 18px; border-radius:8px; 
      font-size:1.08em; font-weight:bold; display:inline-block;
      margin-bottom:1rem;">
      🚧 Edit Route is an <b>experimental feature</b> and is currently in testing. Results may be unpredictable!
    </span>
  `;
  isEditing = true;
  editBtn.style.display = 'none';
  saveEditBtn.style.display = '';
  undoEditBtn.style.display = '';
  redoEditBtn.style.display = '';
  bulkAddBtn.style.display = '';
  bulkDeleteBtn.style.display = '';
  exitEditBtn.style.display = '';
  editHelp.style.display = '';
  redoHistory = [];
  bulkAddBtn.classList.remove('active');
  bulkDeleteBtn.classList.remove('active');
  setBulkMode(null);

  // Create editable polyline
  editablePolyline = L.polyline(points.map(p => [p.lat, p.lng]), { color: '#ff9500', weight: 5 }).addTo(map);
  editablePolyline.enableEdit();
  editHistory = [editablePolyline.getLatLngs().map(ll => ({ lat: ll.lat, lng: ll.lng }))];
  originalPoints = editablePolyline.getLatLngs().map(ll => ({ lat: ll.lat, lng: ll.lng }));

  editablePolyline.on('editable:vertex:dragend editable:vertex:deleted editable:vertex:new', () => {
    if (!bulkMode) { // Only in normal mode!
      editHistory.push(editablePolyline.getLatLngs().map(ll => ({ lat: ll.lat, lng: ll.lng })));
      redoHistory = [];
      saveEditBtn.disabled = editablePolyline.getLatLngs().length < 2;
    }
  });
  if (trailPolyline) map.removeLayer(trailPolyline);
  map.fitBounds(editablePolyline.getBounds(), { padding: [30,30], animate: true });
  saveEditBtn.disabled = editablePolyline.getLatLngs().length < 2;
};

// --- UNDO/REDO ---
undoEditBtn.onclick = function() {
  if (editHistory.length > 1) {
    redoHistory.push(editHistory.pop());
    const last = editHistory[editHistory.length - 1];
    editablePolyline.setLatLngs(last.map(p => [p.lat, p.lng]));
    saveEditBtn.disabled = editablePolyline.getLatLngs().length < 2;
  }
};
redoEditBtn.onclick = function() {
  if (redoHistory.length > 0) {
    const next = redoHistory.pop();
    editHistory.push(next);
    editablePolyline.setLatLngs(next.map(p => [p.lat, p.lng]));
    saveEditBtn.disabled = editablePolyline.getLatLngs().length < 2;
  }
};

// --- EXIT EDIT MODE (Cancel All Edits) ---
exitEditBtn.onclick = function() {
  if (editablePolyline) {
    editablePolyline.remove();
    editablePolyline = null;
  }
  editExperimentalBanner.style.display = 'none';
  if (trailPolyline) map.removeLayer(trailPolyline);
  trailPolyline = L.polyline(originalPoints.map(p => [p.lat, p.lng]), { color: '#007bff', weight: 3, opacity: 0.7 }).addTo(map);
  isEditing = false;
  setBulkMode(null);
  editExperimentalBanner.style.display = 'none';
  bulkAddBtn.style.display = 'none';
  bulkDeleteBtn.style.display = 'none';
  exitEditBtn.style.display = 'none';
  saveEditBtn.style.display = 'none';
  undoEditBtn.style.display = 'none';
  redoEditBtn.style.display = 'none';
  editBtn.style.display = '';
  editHelp.style.display = 'none';
  clearGhostsAndHighlights();
  editModeHint.innerHTML = '';
};

// --- BULK TOOL BUTTONS ---
bulkAddBtn.onclick = () => setBulkMode(bulkMode === 'add' ? null : 'add');
bulkDeleteBtn.onclick = () => setBulkMode(bulkMode === 'delete' ? null : 'delete');

// --- BULK INTERACTIONS (Optimized) ---
map.on('mousedown touchstart', function(e) {
  if (!isEditing || !bulkMode) return;
  map.dragging.disable();
  if (editablePolyline && editablePolyline.editor) {
    editablePolyline.editor.disable();
  }

  brushPath = [e.latlng];
  clearGhostsAndHighlights();
  let color = bulkMode === 'add' ? '#21c821' : '#ff3333';
  let lineOptions = { color, weight: 6, opacity: 0.3, dashArray: '8 8' };
  brushLayer = L.polyline([e.latlng], lineOptions).addTo(map);

  function onMove(ev) {
    let now = Date.now();
    if (now - lastBrushMove < 30) return; // Debounce for perf
    lastBrushMove = now;
    let latlng;
    if (ev.latlng) {
      latlng = ev.latlng;
    } else if (ev.touches && ev.touches[0]) {
      latlng = map.mouseEventToLatLng(ev.touches[0]);
    }
    if (!latlng) return;
    brushPath.push(latlng);
    brushLayer.setLatLngs(brushPath);

    if (bulkMode === 'delete') {
      highlightPolylinePointsBulk(editablePolyline, brushPath, 22);
    }
    if (bulkMode === 'add') {
      if (ghostAddLine) map.removeLayer(ghostAddLine);
      ghostAddLine = L.polyline(brushPath, { color: '#21c821', weight: 5, opacity: 0.5, dashArray: '1 12' }).addTo(map);
    }
  }

  function onUp(ev) {
    map.off('mousemove', onMove);
    map.off('mouseup', onUp);
    map.off('touchmove', onMove);
    map.off('touchend', onUp);

    // --- BULK DELETE ---
    if (bulkMode === 'delete') {
      if (editablePolyline) {
        const idxs = getPolylinePointsInBrush(editablePolyline, brushPath, 22);
        if (idxs.length > 0) {
          const latlngs = editablePolyline.getLatLngs();
          idxs.sort((a, b) => b - a).forEach(idx => latlngs.splice(idx, 1));
          editablePolyline.setLatLngs(latlngs);
          editHistory.push(latlngs.map(ll => ({ lat: ll.lat, lng: ll.lng })));
          redoHistory = [];
          saveEditBtn.disabled = latlngs.length < 2;
          showToast(`Deleted ${idxs.length} point${idxs.length > 1 ? "s" : ""}.`, "delete");
        }
      }
    }

    // --- BULK ADD ---
    if (bulkMode === 'add' && ghostAddLine) {
      if (editablePolyline) {
        let latlngs = editablePolyline.getLatLngs();
        let toAdd = brushPath.slice(1).map(ll => ({ lat: ll.lat, lng: ll.lng }));
        if (toAdd.length > 0) {
          // If the last existing point is far from the first new point, insert a gap marker (null) to force new segment
          const lastPt = latlngs.length ? latlngs[latlngs.length-1] : null;
          if (
            lastPt &&
            L.latLng(lastPt).distanceTo(L.latLng(toAdd[0])) > 500 // >500m = likely intentional
          ) {
            // Insert a break by pushing a marker object with a 'gap' property
            // For now: insert a marker with {gap: true} to split later
            latlngs.push({ gap: true });
          }
          // Add new points after gap (or append if close)
          latlngs = latlngs.concat(toAdd);
          editablePolyline.setLatLngs(latlngs.filter(pt => !pt.gap).map(ll => [ll.lat, ll.lng])); // Visual update (will connect all points for now)
          editHistory.push(latlngs.map(ll => (ll.lat && ll.lng ? { lat: ll.lat, lng: ll.lng } : { gap: true })));
          redoHistory = [];
          saveEditBtn.disabled = latlngs.filter(pt => pt.lat && pt.lng).length < 2;
          showToast(`Added ${toAdd.length} point${toAdd.length > 1 ? "s" : ""}.`, "add");
        }
      }
    }
    clearGhostsAndHighlights();
    brushPath = [];
    if (!bulkMode && editablePolyline && editablePolyline.editor) {
      editablePolyline.editor.enable();
    }
    map.dragging.enable();
  }

  map.on('mousemove', onMove);
  map.on('mouseup', onUp);
  map.on('touchmove', onMove);
  map.on('touchend', onUp);
});

// --- VISUAL FEEDBACK HELPERS ---
function highlightPolylinePointsBulk(polyline, path, pxTolerance) {
  highlightedDeleteMarkers.forEach(m => map.removeLayer(m));
  highlightedDeleteMarkers = [];
  if (!polyline) return;
  const latlngs = polyline.getLatLngs();
  for (let i = 0; i < latlngs.length; i++) {
    for (let j = 1; j < path.length; j++) {
      const p1 = map.latLngToContainerPoint(path[j - 1]);
      const p2 = map.latLngToContainerPoint(path[j]);
      const pt = map.latLngToContainerPoint(latlngs[i]);
      const d = pointToSegmentDistance(pt, p1, p2);
      if (d < pxTolerance) {
        const marker = L.circleMarker(latlngs[i], {
          radius: 9, color: '#ff3333', weight: 2, fillColor: '#fff', fillOpacity: 0.7,
          className: 'bulk-delete-highlight'
        }).addTo(map);
        highlightedDeleteMarkers.push(marker);
        break;
      }
    }
  }
}
function getPolylinePointsInBrush(polyline, path, pxTolerance) {
  const idxs = [];
  const latlngs = polyline.getLatLngs();
  for (let i = 0; i < latlngs.length; i++) {
    for (let j = 1; j < path.length; j++) {
      const p1 = map.latLngToContainerPoint(path[j - 1]);
      const p2 = map.latLngToContainerPoint(path[j]);
      const pt = map.latLngToContainerPoint(latlngs[i]);
      const d = pointToSegmentDistance(pt, p1, p2);
      if (d < pxTolerance) {
        idxs.push(i);
        break;
      }
    }
  }
  return Array.from(new Set(idxs));
}
function pointToSegmentDistance(p, v, w) {
  const l2 = v.distanceTo(w) ** 2;
  if (l2 === 0) return p.distanceTo(v);
  let t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2;
  t = Math.max(0, Math.min(1, t));
  return p.distanceTo(L.point(v.x + t * (w.x - v.x), v.y + t * (w.y - v.y)));
}

// --- TOAST/SNACKBAR ---
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

// --- Polyline Splitter: Split by gap AND explicit gap markers (for multi-segment GPX export) ---
function splitPolylineByGap(latlngs, gapFactor = 5) {
  if (latlngs.length < 2) return [latlngs.filter(pt => pt.lat && pt.lng)];
  // Compute average segment length
  let dists = [];
  for (let i = 1; i < latlngs.length; i++) {
    if (latlngs[i].gap) continue;
    if (latlngs[i-1].gap) continue;
    if (!latlngs[i].lat || !latlngs[i].lng) continue;
    if (!latlngs[i-1].lat || !latlngs[i-1].lng) continue;
    dists.push(L.latLng(latlngs[i-1]).distanceTo(L.latLng(latlngs[i])));
  }
  const avg = dists.length ? dists.reduce((a, b) => a + b, 0) / dists.length : 0;
  let segments = [];
  let current = [];
  for (let i = 0; i < latlngs.length; i++) {
    if (latlngs[i].gap) {
      if (current.length > 1) segments.push(current);
      current = [];
      continue;
    }
    if (i > 0 && !latlngs[i-1].gap && avg && L.latLng(latlngs[i-1]).distanceTo(L.latLng(latlngs[i])) > gapFactor * avg) {
      if (current.length > 1) segments.push(current);
      current = [];
    }
    current.push(latlngs[i]);
  }
  if (current.length > 1) segments.push(current);
  return segments;
}

// --- SAVE AS NEW ROUTE (Export all segments robustly) ---
saveEditBtn.onclick = function() {
  if (!editablePolyline) return;
  // Get all points, including gap markers
  const editedLatLngs = editablePolyline.getLatLngs().map(pt => ({ lat: pt.lat, lng: pt.lng }));

  // If we've inserted gap markers, reconstruct the full points array (with gaps)
  // NOTE: If using Leaflet.Editable, only actual LatLngs are kept in polyline, so any explicit "gap" markers must be tracked in editHistory!
  let fullLatLngs = editHistory.length ? editHistory[editHistory.length-1] : editedLatLngs;

  // --- Find contiguous segments ---
  let segments = splitPolylineByGap(fullLatLngs, 5);

  if (!segments.length) {
    alert("No valid segments to save!");
    return;
  }

  // Warn if there are multiple segments
  if (segments.length > 1) {
    if (!confirm(`Your edited route has ${segments.length} segments (gaps were detected).\nAll segments will be saved in one GPX file.`)) {
      return;
    }
  }

  const title = prompt("Enter a name for your new route:");
  if (!title) return;

  // Export *all* segments in GPX (each as <trkseg>)
  const gpxString = generateMinimalGPX(segments, title);
  const blob = new Blob([gpxString], { type: "application/gpx+xml" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = `${title.replace(/\s+/g, "_")}.gpx`;
  document.body.appendChild(a); a.click(); document.body.removeChild(a);
  URL.revokeObjectURL(url);

  // Remove edit mode UI, reset
  editablePolyline.remove();
  editablePolyline = null;
  isEditing = false;
  setBulkMode(null);
  bulkAddBtn.style.display = 'none';
  bulkDeleteBtn.style.display = 'none';
  exitEditBtn.style.display = 'none';
  saveEditBtn.style.display = 'none';
  undoEditBtn.style.display = 'none';
  redoEditBtn.style.display = 'none';
  editBtn.style.display = '';
  editHelp.style.display = 'none';
  clearGhostsAndHighlights();
  // Optionally: render the new route as main polyline
  if (trailPolyline) map.removeLayer(trailPolyline);
  trailPolyline = L.polyline(segments[0].map(p => [p.lat, p.lng]), { color: '#007bff', weight: 3, opacity: 0.7 }).addTo(map);
};

// --- GPX GENERATION SUPPORTING MULTI-SEGMENT ---
function generateMinimalGPX(segments, name = "Edited Route") {
  // segments: Array of arrays of {lat, lng} objects
  return `<?xml version="1.0"?>
<gpx version="1.1" creator="Memory Lanes Ride Journal" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>${sanitizeString(name)}</name>
    ${segments.map(seg => `
      <trkseg>
        ${seg.map(p => `<trkpt lat="${p.lat}" lon="${p.lng}"></trkpt>`).join('\n')}
      </trkseg>
    `).join('\n')}
  </trk>
</gpx>`;
}

function sanitizeString(str) {
  // Simple sanitizer for titles
  return String(str).replace(/[<>&"]/g, c =>
    ({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;'}[c])
  );
}


  // =====================================================
  // SECTION 6: NAV/ACTION BUTTONS & UI INTERACTIONS
  // =====================================================

  
  uploadAnotherBtn.addEventListener('click', () => {
    rideTitleDisplay.textContent = '';
    document.getElementById('ride-controls').style.display = 'none';
    resetUIToInitial();
    history.replaceState({}, document.title, window.location.pathname);
  });

  showAnalyticsBtn.addEventListener('click', showAnalyticsSection);

  // =====================================================
  // SECTION 7: GPX FILE UPLOAD
  // =====================================================
  uploadInput.addEventListener('change', async e => {
    const file = e.target.files[0];
    if (!file) return;
    const { data: { user } } = await supabase.auth.getUser();
    showUIAfterUpload(!!user);
    if (window.playInterval) clearInterval(window.playInterval);
    if (marker)       map.removeLayer(marker);
    if (trailPolyline) map.removeLayer(trailPolyline);
    points = []; breakPoints = []; cumulativeDistance = []; speedData = []; accelData = [];
    const reader = new FileReader();
    reader.onload = ev => parseAndRenderGPX(ev.target.result);
    reader.readAsText(file);
    hideAnalyticsSection();
  });


  // ========== CHARTS, ANALYTICS, PLAYBACK, SPEED BIN ==========
  function setupChart() {
    const ctx = document.getElementById('elevationChart').getContext('2d');
    if (elevationChart) elevationChart.destroy();
    elevationChart = new Chart(ctx, {
      type: 'line',
      data: {
        datasets: [
          {
            label: 'Elevation',
            data: points.map((p, i) => ({ x: cumulativeDistance[i]/1000, y: p.ele, idx: i })),
            borderColor: '#64ffda',
            backgroundColor: (() => {
              const g = ctx.createLinearGradient(0,0,0,200);
              g.addColorStop(0, 'rgba(100,255,218,0.4)');
              g.addColorStop(1, 'rgba(100,255,218,0)');
              return g;
            })(),
            borderWidth: 2,
            tension: 0.3,
            pointRadius: 0,
            fill: true,
            yAxisID: 'yElevation'
          },
          {
            label: 'Point in Ride',
            data: [{ x: 0, y: points[0] ? points[0].ele : 0 }],
            type: 'scatter',
            pointRadius: 5,
            pointBackgroundColor: '#fff',
            showLine: false,
            yAxisID: 'yElevation'
          },
          {
            label: 'Breaks',
            data: breakPoints.map(i => ({ x: cumulativeDistance[i]/1000, y: points[i].ele })),
            type: 'scatter',
            pointRadius: 3,
            pointBackgroundColor: 'rgba(150,150,150,0.6)',
            showLine: false,
            yAxisID: 'yElevation'
          },
          {
            label: 'Speed (km/h)',
            data: points.map((p, i) => ({ x: cumulativeDistance[i]/1000, y: speedData[i], idx: i })),
            borderColor: '#ff6384',
            backgroundColor: (() => {
              const g = ctx.createLinearGradient(0, 0, 0, 200);
              g.addColorStop(0, 'rgba(255,99,132,0.4)');
              g.addColorStop(1, 'rgba(255,99,132,0)');
              return g;
            })(),
            borderWidth: 2,
            tension: 0.3,
            pointRadius: 0,
            fill: true,
            yAxisID: 'ySpeed'
          }
        ]
      },
      options: {
        responsive: true,
        animation: false,
        interaction: { mode: 'nearest', intersect: false },
        onClick: function(evt) {
          if (window.playInterval) {
            clearInterval(window.playInterval);
            window.playInterval = null;
            playBtn.textContent = '▶️ Play';
          }
          const elements = this.getElementsAtEventForMode(evt,'nearest',{ intersect:false },true);
          if (!elements.length) return;
          const dataPoint = this.data.datasets[elements[0].datasetIndex].data[elements[0].index];
          if (dataPoint && typeof dataPoint.idx === 'number') {
            window.jumpToPlaybackIndex(dataPoint.idx);
          }
        },
        scales: {
          x: {
            type: 'linear',
            title: { display: true, text: 'Distance (km)' },
            grid: { color: '#223' },
            ticks: { callback: v => v.toFixed(2) }
          },
          yElevation: {
            display: true,
            position: 'left',
            title: { display: true, text: 'Elevation (m)' },
            grid: { color: '#334' }
          },
          ySpeed: {
            title: { display: true, text: 'Speed (km/h)' },
            position: 'right',
            min: 0,
            grid: { drawOnChartArea: false },
            ticks: {
              stepSize: 20,
              callback: v => v.toFixed(0)
            }
          }
        },
        plugins: {
          legend: { display: true },
          tooltip: {
            callbacks: { label: ctx => `${ctx.dataset.label}: ${ctx.raw.y.toFixed(1)}` }
          }
        }
      }
    });

    document.querySelectorAll('input[name="chartMode"]').forEach(radio => {
      radio.addEventListener('change', () => {
        const mode = document.querySelector('input[name="chartMode"]:checked').value;
        elevationChart.data.datasets.forEach(ds => {
          if (ds.label === 'Elevation' || ds.label === 'Breaks') ds.hidden = (mode === 'speed');
          else if (ds.label === 'Speed (km/h)') ds.hidden = (mode === 'elevation');
        });
        elevationChart.options.scales.yElevation.display = (mode !== 'speed');
        elevationChart.options.scales.ySpeed.display     = (mode !== 'elevation');
        elevationChart.update();
      });
    });
  }

  function renderAccelChart(accelData, dist, speed, selectedBins, bins) {
    const ctx = document.getElementById('accelChart')?.getContext('2d');
    if (!ctx) return;
    if (window.accelChart && typeof window.accelChart.destroy === 'function') {
      window.accelChart.destroy();
    }

    const accel = dist.map((x, i) => {
      const y = accelData[i];
      return Number.isFinite(y) ? { x: x / 1000, y } : null;
    }).filter(Boolean);

    let highlightPoints = dist.map((x, i) => {
      const y = speed[i];
      return Number.isFinite(y) ? { x: x / 1000, y, idx: i } : null;
    }).filter(Boolean);

    if (selectedBins.length > 0) {
      highlightPoints = highlightPoints.filter(p =>
        selectedBins.some(binIdx => p.y >= bins[binIdx].min && p.y < bins[binIdx].max)
      );
    }

    const accelValues = accel.map(p => p.y);
    const accelMin = Math.min(...accelValues);
    const accelMax = Math.max(...accelValues);
    const accelBuffer = (accelMax - accelMin) * 0.1 || 1;

    const datasets = [
      {
        label: 'Point in Ride',
        data: [{ x: 0, y: 0 }],
        type: 'scatter',
        pointRadius: 5,
        pointBackgroundColor: '#ffffff',
        borderColor: '#ffffff',
        showLine: false,
        yAxisID: 'y'
      },
      {
        label: 'Acceleration',
        data: accel,
        borderColor: '#0168D9',
        borderWidth: 2,
        pointRadius: 0,
        fill: false,
        yAxisID: 'y'
      },
      {
        label: 'Highlighted Speeds',
        data: highlightPoints,
        type: 'scatter',
        pointRadius: 4,
        pointBackgroundColor: '#8338EC',
        borderColor: '#8338EC',
        borderWidth: 1,
        showLine: false,
        yAxisID: 'ySpeed'
      }
    ];

    window.accelChart = new Chart(ctx, {
      type: 'line',
      data: { datasets },
      options: {
        responsive: true,
        animation: false,
        interaction: { mode: 'nearest', intersect: false },
        onClick: function(evt) {
          if (window.playInterval) {
            clearInterval(window.playInterval);
            window.playInterval = null;
            playBtn.textContent = '▶️ Play';
          }
          const elements = this.getElementsAtEventForMode(evt,'nearest',{ intersect:false },true);
          if (!elements.length) return;
          const dataPoint = this.data.datasets[elements[0].datasetIndex].data[elements[0].index];
          if (dataPoint && typeof dataPoint.idx === 'number') {
            window.jumpToPlaybackIndex(dataPoint.idx);
          }
        },
    scales: {
      x: {
        type: 'linear',
        title: {
          display: true,
          text: 'Distance (km)',
            color: '#4C525B',
              font: { size: 14, weight: 'bold', family: "'Inter', 'Roboto', 'Arial', sans-serif" },
                padding: { top: 12 }
        },
        ticks: { callback: v => v.toFixed(2) },
        grid: { color: '#223' }
      },
      y: {
        title: {
          display: true,
          text: 'Acceleration (m/s²)',
            color: '#4C525B',
              font: { size: 14, weight: 'bold', family: "'Inter', 'Roboto', 'Arial', sans-serif" },
                padding: { top: 12 }
        },
        position: 'left',
        min: accelMin - accelBuffer,
        max: accelMax + accelBuffer,
        grid: { color: '#334' }
      },
      ySpeed: {
        title: {
          display: true,
          text: 'Speed (km/h)',
            color: '#4C525B',
              font: { size: 14, weight: 'bold', family: "'Inter', 'Roboto', 'Arial', sans-serif" },
                padding: { top: 12 }
        },
        position: 'right',
        grid: { drawOnChartArea: false }
      }
    },
        plugins: {
          legend: { display: true },
          tooltip: {
            callbacks: {
              label: ctx => `${ctx.dataset.label}: ${ctx.raw.y.toFixed(2)}`
            }
          }
        }
      }
    });
  }

  function renderSpeedFilter() {
    const container = document.getElementById('speed-bins');
    container.innerHTML = '';
    speedBins.forEach((bin, i) => {
      const btn = document.createElement('button');
      btn.textContent = bin.label;
      btn.classList.add('speed-bin-btn');
      btn.dataset.index = i;
      btn.addEventListener('click', () => highlightSpeedBin(i));
      container.appendChild(btn);
    });
  }
  function highlightSpeedBin(i) {
    const btn = document.querySelector(`#speed-bins .speed-bin-btn[data-index="${i}"]`);
    const isActive = selectedSpeedBins.has(i);
    isActive ? selectedSpeedBins.delete(i) : selectedSpeedBins.add(i);
    btn.classList.toggle('active', !isActive);
    if (speedHighlightLayer) map.removeLayer(speedHighlightLayer);
    if (selectedSpeedBins.size === 0) {
      renderAccelChart(accelData, cumulativeDistance, speedData, [], speedBins);
      return;
    }
    const segments = [];
    for (let j = 1; j < points.length; j++) {
      const speed = speedData[j];
      for (let b of selectedSpeedBins) {
        if (speed >= speedBins[b].min && speed < speedBins[b].max) {
          segments.push([[points[j-1].lat, points[j-1].lng], [points[j].lat, points[j].lng]]);
          break;
        }
      }
    }
    speedHighlightLayer = L.layerGroup(segments.map(seg => L.polyline(seg, { color: '#8338ec', weight: 5, opacity: 0.8 }))).addTo(map);
    renderAccelChart(accelData, cumulativeDistance, speedData, Array.from(selectedSpeedBins), speedBins);
  }

  // ========== CORNER CHART & ANALYTICS ==========
  window.Analytics = {
    initAnalytics: function(points, speedData, cumulativeDistance) {
      const angleDegs = Array(points.length).fill(0);
      const accelData = [0];
      for (let i = 1; i < points.length - 1; i++) {
        const p0 = points[i - 1], p1 = points[i], p2 = points[i + 1];
        const v1 = { x: p1.lng - p0.lng, y: p1.lat - p0.lat };
        const v2 = { x: p2.lng - p1.lng, y: p2.lat - p1.lat };
        const dot = v1.x * v2.x + v1.y * v2.y;
        const m1 = Math.hypot(v1.x, v1.y), m2 = Math.hypot(v2.x, v2.y);
        if (m1 && m2) {
          const cosA = Math.min(1, Math.max(-1, dot / (m1 * m2)));
          angleDegs[i] = Math.acos(cosA) * 180 / Math.PI;
        }
      }
      for (let i = 1; i < speedData.length; i++) {
        const dt = (points[i].time - points[i - 1].time) / 1000;
        const dv = speedData[i] - speedData[i - 1];
        accelData[i] = dt ? (dv / dt) * (1000 / 3600) : 0;
      }
      requestAnimationFrame(() => renderCornerChart(angleDegs, speedData));
      window.accelData = accelData;
    }
  };

  function renderCornerChart(angleDegs, speedData) {
    const cornerThreshold = 20;
    const cornerPts = [], straightPts = [];
    angleDegs.forEach((ang, i) => {
      if (i === 0) return;
      const pt = { x: ang, y: speedData[i], idx: i };
      (ang > cornerThreshold ? cornerPts : straightPts).push(pt);
    });

    const ctx = document.getElementById('cornerChart').getContext('2d');
    new Chart(ctx, {
      type: 'scatter',
      data: {
        datasets: [
          { label: 'Corners', data: cornerPts, pointBackgroundColor: '#8338EC' },
          { label: 'Straights', data: straightPts, pointBackgroundColor: '#FF6384' }
        ]
      },
      options: {
        responsive: true,
        animation: false,
        interaction: { mode: 'nearest', intersect: false },
        onClick: function(evt) {
          const elements = this.getElementsAtEventForMode(evt, 'nearest', { intersect: false }, true);
          if (!elements.length) return;
          const dataPoint = this.data.datasets[elements[0].datasetIndex].data[elements[0].index];
          if (dataPoint && typeof dataPoint.idx === 'number') {
            window.jumpToPlaybackIndex(dataPoint.idx);
          }
        },
        plugins: {
      tooltip: {
        callbacks: {
          label: ctx => `Angle: ${ctx.raw.x.toFixed(1)}°, Speed: ${ctx.raw.y.toFixed(1)} km/h`
        }
      }
    },
    scales: {
      x: {
        type: 'linear',
        title: {
          display: true,
          text: 'Turn Angle (°)',
            color: '#4C525B',
              font: { size: 14, weight: 'bold', family: "'Inter', 'Roboto', 'Arial', sans-serif" },
                padding: { top: 12 }
        },
        grid: { color: '#223' }
      },
      y: {
        title: {
          display: true,
          text: 'Speed (km/h)',
            color: '#4C525B',
              font: { size: 14, weight: 'bold', family: "'Inter', 'Roboto', 'Arial', sans-serif" },
                padding: { top: 12 }
        },
        grid: { color: '#334' }
      }
    }
  }
});
}

  // ========== TIMELINE / PLAYBACK ==========
  window.jumpToPlaybackIndex = function(idx) {
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      playBtn.textContent = '▶️ Play';
    }
    document.getElementById('replay-slider').value = idx;
    window.fracIndex = idx;
    updatePlayback(idx);
  }

  window.updatePlayback = idx => {
    const p = points[idx];
    if (!marker) {
      marker = L.circleMarker([p.lat, p.lng], { radius: 6, color: '#007bff', fillColor: '#007bff', fillOpacity: 0.9 }).addTo(map);
    } else {
      marker.setLatLng([p.lat, p.lng]);
    }
    trailPolyline.setLatLngs(points.slice(0, idx + 1).map(pt => [pt.lat, pt.lng]));
    map.panTo([p.lat, p.lng], { animate: false });

    const distKm = (cumulativeDistance[idx]/1000).toFixed(2);
    const mode = document.querySelector('input[name="chartMode"]:checked')?.value || 'elevation';
    const posDs = elevationChart.data.datasets.find(d => d.label === 'Point in Ride');
    posDs.yAxisID = mode === 'speed' ? 'ySpeed' : 'yElevation';
    posDs.data[0] = { x: parseFloat(distKm), y: mode === 'speed' ? speedData[idx] : p.ele };
    elevationChart.update('none');

    if (window.accelChart) {
      const accelCursor = window.accelChart.data.datasets.find(d => d.label === 'Point in Ride');
      if (accelCursor) {
        accelCursor.data[0] = { x: parseFloat(distKm), y: accelData[idx] };
        window.accelChart.update('none');
      }
    }

    slider.value = idx;
    document.getElementById('telemetry-elevation').textContent = `${p.ele.toFixed(0)} m`;
    document.getElementById('telemetry-distance').textContent = `${distKm} km`;
    document.getElementById('telemetry-speed').textContent = `${speedData[idx].toFixed(1)} km/h`;

    const posAccelDs = window.accelChart?.data?.datasets?.find(d => d.label === 'Point in Ride');
    if (posAccelDs) {
      posAccelDs.yAxisID = mode === 'speed' ? 'ySpeed' : 'y';
      posAccelDs.data[0] = {
        x: parseFloat(distKm),
        y: mode === 'speed' ? speedData[idx] : accelData[idx]
      };
      window.accelChart.update('none');
    }
  };

  playBtn.addEventListener('click', () => {
    if (!points.length) return;
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      playBtn.textContent = '▶️ Play';
      return;
    }
    window.fracIndex = Number(slider.value);
    playBtn.textContent = '⏸ Pause';
    const mult = parseFloat(speedSel.value) || 1;
    window.playInterval = setInterval(() => {
      window.fracIndex += mult;
      const idx = Math.floor(window.fracIndex);
      if (idx >= points.length) {
        clearInterval(window.playInterval);
        window.playInterval = null;
        playBtn.textContent = '🔁 Replay';
        return;
      }
      updatePlayback(idx);
    }, FRAME_DELAY_MS);
  });

  slider.addEventListener('input', () => {
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      playBtn.textContent = '▶️ Play';
    }
    updatePlayback(Number(slider.value));
  });

  // ========== AUTH / SAVE LOGIC ==========
document.getElementById('login-btn').addEventListener('click', async () => {
  const email = document.getElementById('auth-email').value;
  const pass = document.getElementById('auth-password').value;
  const statusEl = document.getElementById('auth-status');
  const { data, error } = await supabase.auth.signInWithPassword({ email, password: pass });

  if (error) {
    statusEl.textContent = `❌ Login failed: ${error.message}`;
    return;
  }

  // Clear old messages
  document.getElementById('save-status').textContent = '';
  statusEl.textContent = '✅ Login successful!';
  statusEl.classList.add('status-fade');
  statusEl.style.display = 'block';
  statusEl.style.color = '#64ffda';
  statusEl.style.padding = '0.75rem';
  statusEl.style.fontWeight = 'bold';
  statusEl.style.border = '1px solid #64ffda';
  statusEl.style.background = '#112240';
  statusEl.style.borderRadius = '5px';
  statusEl.style.marginTop = '1rem';

  // Hide login and show save form
  setTimeout(() => {
    authSection.style.display = 'none';
    saveForm.style.display = 'block';
  }, 50);

  // Optional: flash visual feedback (login success only)
  statusEl.textContent = '✅ Login successful!';
});


  document.getElementById('signup-btn').addEventListener('click', async () => {
    const email = document.getElementById('auth-email').value;
    const pass = document.getElementById('auth-password').value;
    const { data, error } = await supabase.auth.signUp({ email, password: pass });
    document.getElementById('auth-status').textContent = error
      ? 'Signup failed: ' + error.message
      : 'Signup OK! Check your email, then login above.';
  });

saveBtn.addEventListener('click', async () => {
  const title = document.getElementById('ride-title').value.trim();
  const statusEl = document.getElementById('save-status');
  statusEl.textContent = ''; // Clear old

  // Check title
  if (!title) {
    showToast('❗ Please enter a ride title.', "info");
    return;
  }

  // Check session
  const sessionResult = await supabase.auth.getSession();
  const user = sessionResult.data?.session?.user;
  if (!user) {
    // Show login section and only show "You must be logged in" if triggered by this error
    authSection.style.display = 'block';
    fadeInElement(authSection);
    saveForm.style.display = 'none';
    showToast('❌ You must be logged in to save a ride.', "delete");
    return;
  }

  // Check GPX file
  const file = uploadInput.files[0];
  if (!file) {
    showToast('❗ No GPX file selected.', "info");
    return;
  }

  // File validation for security
  const validTypes = ['application/gpx+xml', 'application/xml', 'text/xml'];
  if (!validTypes.includes(file.type) && !file.name.endsWith('.gpx')) {
    showToast('❌ Invalid file type. Please upload a .gpx file.', "delete");
    return;
  }
  if (file.size > 5 * 1024 * 1024) { // 5 MB limit
    showToast('❌ GPX file is too large (max 5MB).', "delete");
    return;
  }

  // Upload to Supabase Storage
  const ext      = file.name.split('.').pop();
  const stamp    = Date.now();
  const filePath = `${user.id}/${stamp}.${ext}`;
  const { data: uploadData, error: uploadErr } = await supabase
    .storage
    .from('gpx-files')
    .upload(filePath, file);
  if (uploadErr) {
    showToast(`❌ GPX upload failed: ${uploadErr.message}`, "delete");
    return;
  }

  // Prepare data for insertion
  const distance_km  = parseFloat(distanceEl.textContent);
  const duration_min = parseFloat(rideTimeEl.textContent.split('h')[0]) * 60 +
                       (parseFloat(rideTimeEl.textContent.split('h')[1]) || 0);
  const elevation_m  = parseFloat(elevationEl.textContent);
  const ride_date = points[0].time.toISOString();
  const { data: insertData, error: insertErr } = await supabase
    .from('ride_logs')
    .insert({
      title,
      user_id:     user.id,
      distance_km,
      duration_min,
      elevation_m,
      ride_date,
      gpx_path:    uploadData.path
    });
  if (insertErr) {
    showToast(`❌ Save failed: ${insertErr.message}`, "delete");
    return;
  }

  showToast('✅ Ride saved!', "add");
  showFireworks();
  saveForm.style.display = 'none';
  
  // Insert “Go to Dashboard” button
  const navContainer = document.getElementById('ride-card-nav');
  navContainer.innerHTML = ''; // Clear old
  const dashBtn = document.createElement('button');
  dashBtn.textContent = 'Go to Dashboard';
  dashBtn.className = 'btn-muted';
  dashBtn.style.marginLeft = '1.2rem';
  dashBtn.onclick = () => window.location.href = 'dashboard.html';
  navContainer.appendChild(dashBtn);
  
  // Make sure the nav container is visible and fully aligned left
  navContainer.style.display = 'block';
  navContainer.style.marginTop = '1.5rem';
  navContainer.style.padding = '0 0 0 2.3rem';  // aligns with form card padding
  navContainer.style.textAlign = 'left';

  // Hide the persistent dashboard button to prevent duplicate "Go to Dashboard" buttons after saving
  const persistentDashBtn = document.getElementById('dashboard-check-btn');
  if (persistentDashBtn) persistentDashBtn.style.display = 'none';
  
});



// ========== INIT ==========
resetUIToInitial();

// ========== LOAD RIDE FROM DASHBOARD ==========

const params = new URLSearchParams(window.location.search);

if (params.has('ride')) {
  (async () => {
    // Always reset UI messages before a load
    rideTitleDisplay.textContent = '';
    rideTitleDisplay.style.color = '';
    try {
      const { data: ride, error: rideErr } = await supabase
        .from('ride_logs')
        .select('*')
        .eq('id', params.get('ride'))
        .single();

      console.log('Ride:', ride, rideErr);

      if (rideErr || !ride) {
        // Only show error if actually failed
        rideTitleDisplay.textContent = "❌ Failed to load ride. Please try another or return to dashboard.";
        rideTitleDisplay.style.color = "#ff6b6b";
        rideTitleDisplay.style.textAlign = "center";
        document.getElementById('ride-controls').style.display = 'block';
        rideActions.style.display = 'flex';
        return;
      }

      // All clear: update UI!
      console.log('Ride loaded:', ride);

      hideSaveForm();
      rideTitleDisplay.textContent = ride.title
        ? `📍 Viewing: “${ride.title}”`
        : `📍 Viewing Saved Ride`;

      rideTitleDisplay.style.color = ""; // clear any previous error color
      rideTitleDisplay.style.textAlign = "center";
      document.getElementById('ride-controls').style.display = 'block';
      rideActions.style.display = 'flex';

      // GPX fetch
      const { data: urlData, error: urlErr } = supabase
        .storage
        .from('gpx-files')
        .getPublicUrl(ride.gpx_path);
      if (urlErr) throw urlErr;

      const resp = await fetch(urlData.publicUrl);
      const gpxText = await resp.text();
      await parseAndRenderGPX(gpxText);

      // Moments
      rideMoments = Array.isArray(ride.moments) ? ride.moments : [];
      if (momentsSection) {
        momentsSection.style.display = 'block';
        renderMoments();
      }

      showUIForSavedRide();
      hideAnalyticsSection();
      showAnalyticsBtn.style.display = 'inline-block';
    } catch (err) {
      // This only triggers on actual exceptions
      rideTitleDisplay.textContent = "❌ Error loading ride data.";
      rideTitleDisplay.style.color = "#ff6b6b";
      rideTitleDisplay.style.textAlign = "center";
      document.getElementById('ride-controls').style.display = 'block';
      rideActions.style.display = 'flex';
      console.error("Load error", err);
    }
  })();
}

  // === Collapsible Footer Logic ===
const toggleBtn = document.getElementById('footer-toggle');
const content = document.getElementById('footer-content');

if (toggleBtn && content) {
  toggleBtn.addEventListener('click', () => {
    const expanded = content.classList.toggle('expanded');
    toggleBtn.innerText = expanded
      ? '▼ Thanks, legend 🙌'
      : '▲ Like the vibes of the app ☕ Tap to support the developers';
    toggleBtn.setAttribute('aria-expanded', expanded);
  });
}

// === Go to Dashboard Button Logic (Persistent Button) ===
const dashboardBtn = document.getElementById('dashboard-check-btn');

if (dashboardBtn) {
  dashboardBtn.addEventListener('click', async () => {
    const { data: sessionResult } = await supabase.auth.getSession();
    const user = sessionResult?.session?.user;

    if (user) {
      // ✅ Logged in – direct to dashboard
      window.location.href = 'dashboard.html';
    } else {
      // ❌ Not logged in – scroll to login section
      authSection.style.display = 'block';
      fadeInElement(authSection);
      saveForm.style.display = 'none';
      document.getElementById('auth-email').focus();
      document.getElementById('auth-status').textContent = '🔐 Please login to access your dashboard.';
      document.getElementById('auth-status').style.color = '#ffd700';
      document.getElementById('auth-status').style.padding = '0.5rem';
      document.getElementById('auth-status').style.fontWeight = '600';
      authSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  });
}

toggleMomentsBtn.addEventListener('click', () => {
  const isOpen = momentsTools.style.display === 'block';
  momentsTools.style.display = isOpen ? 'none' : 'block';
  toggleMomentsBtn.textContent = isOpen ? 'Add Moments & Journal' : 'Hide Moments & Journal';
});

  
addMomentBtn.addEventListener('click', () => {
  if (rideMoments.length >= 5) {
    showToast('You can only save up to 5 moments for this ride.', 'info');
    return;
  }
  // Use current playback index, or let user click on map (for now, playback index)
  const idx = window.fracIndex || 0;
  const point = points[idx] || points[0];
  const moment = {
    idx,
    lat: point.lat,
    lng: point.lng,
    speed: speedData[idx] || 0,
    elevation: point.ele || 0,
    title: '',
    note: ''
  };
  rideMoments.push(moment);
  saveMomentsToDB();
  renderMoments();
});

});


// =============== CANVAS FIREWORKS CELEBRATION ===============

(function() {
  const canvas = document.getElementById('fireworks-canvas');
  const ctx = canvas.getContext('2d');
  let running = false;

  // Overlay vignette (smooth fade in/out)
  function showOverlay() {
    let overlay = document.getElementById('fireworks-premium-overlay');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'fireworks-premium-overlay';
      overlay.style.cssText = `
        position:fixed;left:0;top:0;width:100vw;height:100vh;
        background:radial-gradient(ellipse at center, rgba(0,0,0,0.42) 60%, rgba(10,15,30,0.76) 100%);
        z-index:99998;pointer-events:none;opacity:0;
        transition:opacity 0.7s cubic-bezier(.77,0,.18,1);`;
      document.body.appendChild(overlay);
    }
    overlay.style.opacity = '1';
    overlay.style.display = 'block';
    return overlay;
  }
  function hideOverlay(overlay) {
    if (overlay) {
      overlay.style.opacity = '0';
      setTimeout(() => { overlay.style.display = 'none'; }, 700);
    }
  }

  // --- Burst Shapes: classic, heart, star, ring ---
  function burstShape(type, n, i) {
    const theta = (i / n) * 2 * Math.PI;
    if (type === 'star') {
      // 5-point star path
      const points = 5, inner = 0.48, outer = 1;
      const starI = i % (points*2);
      return (starI % 2 === 0)
        ? { r: outer, angle: (starI/2) * (2*Math.PI/points) }
        : { r: inner, angle: ((starI-1)/2) * (2*Math.PI/points) + Math.PI/points };
    }
    if (type === 'heart') {
      // Parametric heart curve
      return {
        r: 1.0,
        angle: theta,
        x: 16 * Math.pow(Math.sin(theta),3),
        y: -(13 * Math.cos(theta) - 5*Math.cos(2*theta) - 2*Math.cos(3*theta) - Math.cos(4*theta))
      };
    }
    // Ring (circle)
    return { r: 1, angle: theta };
  }

  function randomColor() {
    const palette = [
      '#64ffda','#ff6384','#ffd700','#fff','#00c6ff','#8338ec','#ffac00','#19ed7d'
    ];
    return palette[Math.floor(Math.random() * palette.length)];
  }

  // --- Particle with trail history ---
  function Particle(props) {
    Object.assign(this, props);
    this.history = [{x:this.x, y:this.y}];
    this.maxTrail = 10 + Math.floor(Math.random()*6);
  }
  Particle.prototype.update = function(gravity, fade) {
    // Add organic "wobble"
    const wobble = 0.3 * Math.sin(this.life*0.2 + this.seed);
    this.x += this.vx + wobble;
    this.y += this.vy;
    this.vy += gravity;
    this.alpha -= fade;
    this.life++;
    this.history.push({x:this.x, y:this.y});
    if (this.history.length > this.maxTrail) this.history.shift();
  };
  Particle.prototype.draw = function(ctx) {
    // Draw trail (fade from oldest to newest)
    for (let j=1;j<this.history.length;j++) {
      ctx.save();
      ctx.globalAlpha = (this.alpha * j / this.history.length) * 0.45;
      ctx.beginPath();
      ctx.moveTo(this.history[j-1].x, this.history[j-1].y);
      ctx.lineTo(this.history[j].x, this.history[j].y);
      ctx.strokeStyle = this.color;
      ctx.lineWidth = Math.max(1, this.size * 0.7 * j / this.history.length);
      ctx.shadowColor = this.color;
      ctx.shadowBlur = 10;
      ctx.stroke();
      ctx.restore();
    }
    // Draw main particle
    ctx.save();
    ctx.globalAlpha = this.alpha;
    ctx.beginPath();
    ctx.arc(this.x, this.y, this.size, 0, 2*Math.PI);
    ctx.fillStyle = this.color;
    ctx.shadowColor = this.color;
    ctx.shadowBlur = 24;
    ctx.fill();
    ctx.restore();
  };

  function Firework() {
    // Randomize burst center
    this.x = Math.random() * canvas.width * 0.65 + canvas.width * 0.175;
    this.y = canvas.height * (0.46 + Math.random() * 0.22);
    this.color = randomColor();
    this.size = 1.0 + Math.random() * 1.1;
    this.vx = (Math.random() - 0.5) * 2.4;
    this.vy = -8.2 - Math.random() * 2.8;
    this.state = "launch";
    this.timer = 0;
    this.maxTimer = 16 + Math.random() * 8;
    // 1 in 8 = special shape burst
    const shapeType = Math.random();
    if (shapeType > 0.875)      this.burstType = "star";
    else if (shapeType > 0.75)  this.burstType = "heart";
    else if (shapeType > 0.625) this.burstType = "ring";
    else                        this.burstType = "classic";
    this.particles = [];
  }
  Firework.prototype.update = function() {
    if (this.state === "launch") {
      this.x += this.vx;
      this.y += this.vy;
      this.vy += 0.19;
      this.timer++;
      if (this.timer >= this.maxTimer || this.vy > 0) {
        this.state = "burst";
        let n = 56 + Math.floor(Math.random() * 32);
        for (let i = 0; i < n; i++) {
          let angle, speed, px, py;
          let baseSize = this.size * (0.67 + Math.random()*0.39);
          let type = this.burstType;
          let shape = burstShape(type, n, i);
          if (type === "star") {
            angle = shape.angle;
            speed = 3.3 + Math.random() * 1.7;
          } else if (type === "heart") {
            // heart-shaped, scaled for burst
            px = this.x + shape.x * 5.4;
            py = this.y + shape.y * 5.4;
            angle = Math.atan2(py-this.y, px-this.x);
            speed = 3.6 + Math.random() * 1.7;
          } else if (type === "ring") {
            angle = shape.angle;
            speed = 5.1 + Math.random() * 0.9;
          } else {
            angle = (i / n) * 2 * Math.PI;
            speed = Math.random() * 4.2 + 2.5;
          }
          let vx = Math.cos(angle) * speed * (type==="heart"?0.6:1);
          let vy = Math.sin(angle) * speed * (type==="heart"?0.7:1);
          this.particles.push(new Particle({
            x: this.x, y: this.y,
            vx: vx, vy: vy,
            alpha: 0.96 + Math.random()*0.16,
            color: randomColor(),
            size: baseSize,
            life: 0,
            seed: Math.random()*1000
          }));
        }
      }
    } else {
      // Physics: gravity increases as particle fades (gently)
      this.particles.forEach(p => p.update(0.048 + 0.017*(1-p.alpha), 0.012 + Math.random() * 0.012));
      this.particles = this.particles.filter(p => p.alpha > 0.04);
    }
  };
  Firework.prototype.draw = function(ctx) {
    if (this.state === "launch") {
      ctx.save();
      ctx.globalAlpha = 0.52 + 0.12 * Math.random();
      ctx.beginPath();
      ctx.arc(this.x, this.y, this.size * 2.0, 0, 2 * Math.PI);
      ctx.fillStyle = "#fff";
      ctx.shadowColor = this.color;
      ctx.shadowBlur = 18;
      ctx.fill();
      ctx.restore();
    } else {
      this.particles.forEach(p => p.draw(ctx));
    }
  };

  window.showFireworks = function(duration = 2000) {
    if (running) return;
    running = true;
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
    canvas.style.display = "block";
    let fireworks = [];
    let start = null;
    let active = true;
    let interval = setInterval(() => {
      if (!active) return;
      const count = 1 + Math.floor(Math.random()*2);
      for (let i = 0; i < count; i++) fireworks.push(new Firework());
    }, 340);

    // Animated overlay
    const overlay = showOverlay();

    function animate(ts) {
      if (!start) start = ts;
      ctx.clearRect(0,0,canvas.width,canvas.height);

      fireworks.forEach(fw => fw.update());
      fireworks.forEach(fw => fw.draw(ctx));
      for (let i=fireworks.length-1; i>=0; i--) {
        if (fireworks[i].state === "burst" && fireworks[i].particles.length === 0)
          fireworks.splice(i, 1);
      }
      if (ts - start < duration) {
        requestAnimationFrame(animate);
      } else if (fireworks.length > 0) {
        active = false;
        clearInterval(interval);
        requestAnimationFrame(animate);
      } else {
        clearInterval(interval);
        setTimeout(() => {
          canvas.style.display = "none";
          running = false;
          hideOverlay(overlay);
        }, 800);
      }
    }
    requestAnimationFrame(animate);
  };
})();
