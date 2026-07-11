// =============================================
// Memory Lanes Ride Journal - script.js
// =============================================

import supabase from './supabaseClient.js';
import { analyzeRide, renderRiderSkills, summarizeForStorage } from './riderskills.js?v=60';
import { buildRideInsights } from './insights.js?v=60';
import { mlIconSVG } from './icons.js?v=60';

document.addEventListener('DOMContentLoaded', async () => {
  // =====================================================
  // SECTION 1: UI ELEMENT REFERENCES & UI STATE HELPERS
  // =====================================================
  
  // Helper: Escape user-entered text before injecting into innerHTML
  function escapeHtml(str) {
    return String(str ?? '').replace(/[&<>"']/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
    );
  }

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
  const reverseEditBtn    = document.getElementById('reverse-edit-btn');
  const connectStartBtn   = document.getElementById('connect-start-edit-btn');
  const simplifyEditBtn   = document.getElementById('simplify-edit-btn');
  const cropEditBtn       = document.getElementById('crop-edit-btn');
  const splitEditBtn      = document.getElementById('split-edit-btn');
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
        <span class="moment-pin-icon">${mlIconSVG('pin')}</span>
        <span>
          <strong>Km:</strong> ${Number.isFinite(cumulativeDistance[m.idx]) ? (cumulativeDistance[m.idx]/1000).toFixed(2) : '--'}<br>
          <strong>Speed:</strong> ${m.speed?.toFixed(1) || '--'} km/h<br>
          <strong>Elevation:</strong> ${m.elevation?.toFixed(0) || '--'} m
        </span>
        <button class="jump-moment-btn btn-muted" data-idx="${i}" style="margin-left:auto;">Jump</button>
        <button class="delete-moment-btn btn-muted" data-idx="${i}" style="margin-left:0.8rem;color:#ff6b6b;">${mlIconSVG('trash')}</button>
      </div>
      <input type="text" placeholder="Moment title (optional)" value="${escapeHtml(m.title)}" class="moment-title-input" data-idx="${i}" style="width: 90%; margin-bottom: 0.3rem;" />
      <textarea placeholder="Your notes or memory..." class="moment-note-input" data-idx="${i}" style="width: 90%; min-height: 48px;">${escapeHtml(m.note)}</textarea>
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
      icon: L.divIcon({ className: 'moment-pin', html: `<span style="color:#8338ec;">${mlIconSVG('pin')}</span>` })
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
  if (!rideId) {
    showToast('Save this ride first to keep moments.', 'info');
    return;
  }
  const { error } = await supabase
    .from('ride_logs')
    .update({ moments: rideMoments })
    .eq('id', rideId);
  if (error) showToast('Failed to save moments', 'delete');
}

  
  // ----- UI visibility logic -----
  function setHeroVisible(visible) {
    const hero = document.getElementById('landing-hero');
    if (hero) hero.style.display = visible ? 'block' : 'none';
  }

  function resetUIToInitial() {
    setHeroVisible(true);
    const titleInput = document.getElementById('ride-title');
    if (titleInput) titleInput.value = '';
    if (fileStatus) {
      fileStatus.textContent = 'No file selected';
      fileStatus.classList.remove('ready');
    }
    uploadSection.style.display        = 'block';
    const uc0 = document.querySelector('.upload-controls');
    if (uc0) uc0.style.display = '';
    postUploadActions.style.display    = 'none';
    saveForm.style.display             = 'none';
    authSection.style.display          = 'none';
    mainRideUI.style.display           = 'none';
    analyticsSection.style.display     = 'none';
    showAnalyticsBtn.style.display     = 'none';
    downloadSummary.style.display      = 'none';
    exportVideo.style.display          = 'none';
    if (rideActions) rideActions.style.display = 'none';
    editControls.style.display         = 'none';
    editHelp.style.display             = 'none';
    document.getElementById('gpx-upload').value = '';
  }

  function showUIAfterUpload(isLoggedIn) {
    setHeroVisible(false);
    uploadSection.style.display        = 'block';
    mainRideUI.style.display           = 'block';
    saveForm.style.display             = 'block';
    showAnalyticsBtn.style.display     = 'inline-block';
    analyticsSection.style.display     = 'none';
    downloadSummary.style.display      = 'inline-block';
    exportVideo.style.display          = 'inline-block';
    if (rideActions) rideActions.style.display = 'none';
    authSection.style.display          = isLoggedIn ? 'none' : 'block';
    setTimeout(() => map.invalidateSize(), 200);
    editControls.style.display         = 'flex';
  }

  function showUIForSavedRide() {
    setHeroVisible(false);
    // Keep the toolbar so Download Summary / Export Video work on saved rides,
    // but hide the upload picker itself.
    uploadSection.style.display        = 'block';
    const uc1 = document.querySelector('.upload-controls');
    if (uc1) uc1.style.display = 'none';
    postUploadActions.style.display    = 'flex';
    const uaSaved = document.getElementById('upload-another');
    if (uaSaved) uaSaved.style.display = '';
    mainRideUI.style.display           = 'block';
    saveForm.style.display             = 'none';
    authSection.style.display          = 'none';
    showAnalyticsBtn.style.display     = 'inline-block';
    analyticsSection.style.display     = 'none';
    downloadSummary.style.display      = 'inline-block';
    exportVideo.style.display          = 'inline-block';
    if (rideActions) rideActions.style.display = 'none';
    setTimeout(() => map.invalidateSize(), 200);
    editControls.style.display         = 'flex';
  }

  function showUIForSharedRide() {
    setHeroVisible(false);
    uploadSection.style.display        = 'block';
    const uc2 = document.querySelector('.upload-controls');
    if (uc2) uc2.style.display = 'none';
    postUploadActions.style.display    = 'flex';
    const oj = document.getElementById('open-journal');
    if (oj) oj.style.display = 'none';
    const uaShared = document.getElementById('upload-another');
    if (uaShared) uaShared.style.display = 'none';
    const shareShared = document.getElementById('share-ride-btn');
    if (shareShared) shareShared.style.display = 'none';
    const unshareShared = document.getElementById('unshare-ride-btn');
    if (unshareShared) unshareShared.style.display = 'none';
    mainRideUI.style.display           = 'block';
    saveForm.style.display             = 'none';
    authSection.style.display          = 'none';
    showAnalyticsBtn.style.display     = 'inline-block';
    analyticsSection.style.display     = 'none';
    if (rideActions) rideActions.style.display = 'none';
    editControls.style.display         = 'none';
    editHelp.style.display             = 'none';
    setTimeout(() => map.invalidateSize(), 200);
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
  // Playback button shows an icon, not a text label. States: play | pause | replay.
  function setPlayState(state) {
    if (!playBtn) return;
    playBtn.dataset.state = state;
    playBtn.setAttribute('aria-label',
      state === 'pause' ? 'Pause' : state === 'replay' ? 'Replay' : 'Play');
  }
  // Keeps the scrubber's gradient fill in step with its value.
  function setScrubberFill(el) {
    if (!el) return;
    const max = Number(el.max) || 0;
    const pct = max > 0 ? (Number(el.value) / max) * 100 : 0;
    el.style.setProperty('--pct', pct + '%');
  }
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
    fileStatus.textContent = 'File ready';
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
    })).filter(p =>
      // Use Number.isFinite so 0 (equator / prime meridian) is valid, and
      // check the timestamp is a REAL date (an Invalid Date is still a Date instance).
      Number.isFinite(p.lat) && p.lat >= -90 && p.lat <= 90 &&
      Number.isFinite(p.lng) && p.lng >= -180 && p.lng <= 180 &&
      p.time instanceof Date && !isNaN(p.time.getTime())
    );

    if (!trkpts.length) {
      showToast('That file has no valid GPS trackpoints. Please upload a GPX recorded by a GPS device or app.', 'delete');
      resetUIToInitial();
      return;
    }

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
    if (points.at(-1).time.getTime() !== trkpts.at(-1).time.getTime()) {
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
    distanceEl.innerHTML = `${(cumulativeDistance.at(-1) / 1000).toFixed(2)} <span class="unit">km</span>`;
    durationEl.textContent = `${Math.floor(totMin / 60)}h ${totMin % 60}m`;
    const rideSec = points.reduce((sum, _, i) =>
      i > 0 && !breakPoints.includes(i)
        ? sum + ((points[i].time - points[i-1].time) / 1000)
        : sum, 0);
    const rideMin = Math.floor(rideSec / 60);
    rideTimeEl.textContent   = `${Math.floor(rideMin / 60)}h ${rideMin % 60}m`;
    elevationEl.innerHTML  = `${points.reduce((sum, p, i) =>
      i>0 && p.ele>points[i-1].ele ? sum + (p.ele - points[i-1].ele) : sum, 0).toFixed(0)} <span class="unit">m</span>`;

    // Draw route
    if (trailPolyline) map.removeLayer(trailPolyline);
    trailPolyline = L.polyline(points.map(p => [p.lat, p.lng]), {
      color: '#007bff', weight: 3, opacity: 0.7
    }).addTo(map).bringToBack();

    setTimeout(() => {
      map.invalidateSize();
      if (trailPolyline && points.length > 1) {
        map.fitBounds(trailPolyline.getBounds(), { padding: [30,30], animate: true });
        animateRouteDraw(trailPolyline);
      } else if (points.length === 1) {
        map.setView([points[0].lat, points[0].lng], 13);
      }
    }, 210);

    setupChart();
    renderSpeedFilter();
    [slider, playBtn, summaryBtn, videoBtn, speedSel].forEach(el => el.disabled = false);
    slider.min = 0; slider.max = points.length - 1; slider.value = 0;
    setScrubberFill(slider);
    setPlayState('play');



    hideAnalyticsSection();
    showAnalyticsBtn.style.display = 'inline-block';
    fetchAndShowWeather(); // fire-and-forget: fills the Weather line in the summary

    // ---- Rider Skills: analyze on a high-resolution point stream ----
    // (display pipeline samples every >=5s; skills need ~1s resolution)
    try {
      let skillPts = [];
      let lastT = -Infinity;
      for (const tp of trkpts) {
        const ts = tp.time.getTime();
        if (ts - lastT >= 950) { skillPts.push(tp); lastT = ts; }
      }
      if (skillPts.length > 15000) {
        const stride = Math.ceil(skillPts.length / 15000);
        skillPts = skillPts.filter((_, i) => i % stride === 0);
      }
      const jumpToNearestTime = (date) => {
        if (!points.length) return;
        const target = date.getTime();
        let best = 0, bestD = Infinity;
        for (let i = 0; i < points.length; i++) {
          const d = Math.abs(points[i].time.getTime() - target);
          if (d < bestD) { bestD = d; best = i; }
        }
        window.jumpToPlaybackIndex(best);
      };
      setTimeout(async () => {
        const analysis = analyzeRide(skillPts);
        window.lastAnalysis = analysis;
        const prevScores = await fetchRecentAvgScores(new URLSearchParams(window.location.search).get('ride'));
        renderRiderSkills(analysis, {
          containerId: 'rider-skills-content',
          jumpToTime: jumpToNearestTime,
          prevScores
        });
        if (analysis.ok) {
          renderCornerRadiusChart(analysis, jumpToNearestTime);
          renderAccelProfile(analysis);
          renderGGChart(analysis);
          renderRideInsights(analysis, skillPts);
          lastSkillsSummary = summarizeForStorage(analysis);
          storeSkillsForCurrentRide(lastSkillsSummary);
          enhanceRepeatCorners(analysis);
        }
      }, 0);
    } catch (skillErr) {
      console.warn('Rider skills analysis failed:', skillErr);
    }
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
let cropMode = false;
let splitMode = false;
let cropPoints = []; // up to 2 vertex indices picked while cropMode is on
let cropMarkers = [];

// --- Utility: Visual feedback cleanup ---
function clearGhostsAndHighlights() {
  if (brushLayer) { map.removeLayer(brushLayer); brushLayer = null; }
  if (ghostAddLine) { map.removeLayer(ghostAddLine); ghostAddLine = null; }
  highlightedDeleteMarkers.forEach(m => map.removeLayer(m));
  highlightedDeleteMarkers = [];
}
function clearCropMarkers() {
  cropMarkers.forEach(m => map.removeLayer(m));
  cropMarkers = [];
  cropPoints = [];
}

// --- Toggle Bulk Mode ---
function setBulkMode(mode) {
  if (mode) {
    // Bulk tools are mutually exclusive with crop/split
    cropMode = false;
    splitMode = false;
    clearCropMarkers();
    cropEditBtn.classList.remove('active');
    splitEditBtn.classList.remove('active');
  }
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

// --- Toggle Crop Mode: click two points on the line to keep only what's between them ---
function setCropMode(on) {
  if (on) { setBulkMode(null); setSplitMode(false); }
  cropMode = on;
  clearCropMarkers();
  cropEditBtn.classList.toggle('active', on);
  if (editablePolyline && editablePolyline.editor) {
    if (on) editablePolyline.editor.disable();
    else if (!bulkMode && !splitMode) editablePolyline.editor.enable();
  }
  editModeHint.innerHTML = on ? 'Crop: click the point to keep from, then the point to keep until.' : '';
}

// --- Toggle Split Mode: click one point on the line to export it as two GPX files ---
function setSplitMode(on) {
  if (on) { setBulkMode(null); setCropMode(false); }
  splitMode = on;
  splitEditBtn.classList.toggle('active', on);
  if (editablePolyline && editablePolyline.editor) {
    if (on) editablePolyline.editor.disable();
    else if (!bulkMode && !cropMode) editablePolyline.editor.enable();
  }
  editModeHint.innerHTML = on ? 'Split: click the point where the route should split into two files.' : '';
}

// --- Line click: routes to crop/split handling when one of those tools is active ---
function onEditableLineClick(e) {
  if (!cropMode && !splitMode) return;
  L.DomEvent.stop(e);
  const latlngs = editablePolyline.getLatLngs();
  const clickPt = map.latLngToLayerPoint(e.latlng);
  let bestIdx = 0, bestDist = Infinity;
  latlngs.forEach((ll, i) => {
    const d = clickPt.distanceTo(map.latLngToLayerPoint(ll));
    if (d < bestDist) { bestDist = d; bestIdx = i; }
  });
  if (cropMode) handleCropClick(bestIdx);
  else if (splitMode) handleSplitClick(bestIdx);
}

function handleCropClick(idx) {
  const latlngs = editablePolyline.getLatLngs();
  cropPoints.push(idx);
  const marker = L.circleMarker(latlngs[idx], {
    radius: 7, color: '#fff', weight: 2, fillColor: '#ff3333', fillOpacity: 1
  }).addTo(map);
  cropMarkers.push(marker);

  if (cropPoints.length < 2) {
    editModeHint.innerHTML = 'Crop: now click the point to keep until.';
    return;
  }

  let [a, b] = cropPoints;
  if (a > b) [a, b] = [b, a];
  if (a === b) {
    showToast('Pick two different points.', 'info');
    clearCropMarkers();
    editModeHint.innerHTML = 'Crop: click the point to keep from, then the point to keep until.';
    return;
  }
  const kept = latlngs.slice(a, b + 1);
  if (!confirm(`Keep ${kept.length} of ${latlngs.length} points and discard the rest?`)) {
    setCropMode(false);
    return;
  }
  editablePolyline.setLatLngs(kept);
  editHistory.push(kept.map(ll => ({ lat: ll.lat, lng: ll.lng })));
  redoHistory = [];
  saveEditBtn.disabled = kept.length < 2;
  showToast(`Cropped to ${kept.length} points.`, 'add');
  setCropMode(false);
}

function handleSplitClick(idx) {
  const latlngs = editablePolyline.getLatLngs();
  if (idx < 1 || idx > latlngs.length - 2) {
    showToast("Pick a point that isn't the very start or end.", 'info');
    return;
  }
  const partA = latlngs.slice(0, idx + 1).map(ll => ({ lat: ll.lat, lng: ll.lng }));
  const partB = latlngs.slice(idx).map(ll => ({ lat: ll.lat, lng: ll.lng }));
  if (!confirm(`Split into two files here? Part 1: ${partA.length} points, Part 2: ${partB.length} points.`)) {
    setSplitMode(false);
    return;
  }
  const baseTitle = (rideTitleDisplay.textContent || 'Route')
    .replace(/^Viewing:\s*/, '').replace(/[“”"]/g, '').trim() || 'Route';
  downloadGPXFile([partA], `${baseTitle} (Part 1)`);
  downloadGPXFile([partB], `${baseTitle} (Part 2)`);
  showToast('Downloaded both parts.', 'add');
  setSplitMode(false);
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
      Edit Route is an <b>experimental feature</b> and is currently in testing. Results may be unpredictable!
    </span>
  `;
  isEditing = true;
  editBtn.style.display = 'none';
  saveEditBtn.style.display = '';
  undoEditBtn.style.display = '';
  redoEditBtn.style.display = '';
  bulkAddBtn.style.display = '';
  bulkDeleteBtn.style.display = '';
  reverseEditBtn.style.display = '';
  connectStartBtn.style.display = '';
  simplifyEditBtn.style.display = '';
  cropEditBtn.style.display = '';
  splitEditBtn.style.display = '';
  exitEditBtn.style.display = '';
  editHelp.style.display = '';
  redoHistory = [];
  bulkAddBtn.classList.remove('active');
  bulkDeleteBtn.classList.remove('active');
  cropMode = false;
  splitMode = false;
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
  editablePolyline.on('click', onEditableLineClick);
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
  resetEditModeUI();
};

// --- BULK TOOL BUTTONS ---
bulkAddBtn.onclick = () => setBulkMode(bulkMode === 'add' ? null : 'add');
bulkDeleteBtn.onclick = () => setBulkMode(bulkMode === 'delete' ? null : 'delete');
cropEditBtn.onclick = () => setCropMode(!cropMode);
splitEditBtn.onclick = () => setSplitMode(!splitMode);

// --- REVERSE ROUTE ---
reverseEditBtn.onclick = function() {
  if (!editablePolyline || bulkMode || cropMode || splitMode) return;
  const latlngs = editablePolyline.getLatLngs().slice().reverse();
  editablePolyline.setLatLngs(latlngs);
  editHistory.push(latlngs.map(ll => ({ lat: ll.lat, lng: ll.lng })));
  redoHistory = [];
  saveEditBtn.disabled = latlngs.length < 2;
  showToast('Route direction reversed.', 'add');
};

// --- CONNECT BACK TO START ---
connectStartBtn.onclick = function() {
  if (!editablePolyline || bulkMode || cropMode || splitMode) return;
  const latlngs = editablePolyline.getLatLngs();
  if (latlngs.length < 2) return;
  const first = latlngs[0], last = latlngs[latlngs.length - 1];
  if (first.equals(last)) {
    showToast('Route already returns to the start.', 'info');
    return;
  }
  const newLatLngs = latlngs.concat([L.latLng(first.lat, first.lng)]);
  editablePolyline.setLatLngs(newLatLngs);
  editHistory.push(newLatLngs.map(ll => ({ lat: ll.lat, lng: ll.lng })));
  redoHistory = [];
  saveEditBtn.disabled = false;
  showToast('Return leg added — route now ends where it started.', 'add');
};

// --- SIMPLIFY (reduce excess GPS points, keep the shape) ---
simplifyEditBtn.onclick = function() {
  if (!editablePolyline || bulkMode || cropMode || splitMode) return;
  const latlngs = editablePolyline.getLatLngs();
  if (latlngs.length < 3) {
    showToast('Not enough points to simplify.', 'info');
    return;
  }
  const REF_ZOOM = 15; // fixed zoom so tolerance is consistent regardless of current view
  const projected = latlngs.map(ll => map.project(ll, REF_ZOOM));
  const simplified = L.LineUtil.simplify(projected, 3);
  const newLatLngs = simplified.map(p => map.unproject(p, REF_ZOOM));
  if (newLatLngs.length >= latlngs.length) {
    showToast('Route is already simplified — no points removed.', 'info');
    return;
  }
  const pctCut = Math.round((1 - newLatLngs.length / latlngs.length) * 100);
  if (!confirm(`Reduce from ${latlngs.length} to ${newLatLngs.length} points (about ${pctCut}% fewer)? You can undo this.`)) return;
  editablePolyline.setLatLngs(newLatLngs);
  editHistory.push(newLatLngs.map(ll => ({ lat: ll.lat, lng: ll.lng })));
  redoHistory = [];
  saveEditBtn.disabled = newLatLngs.length < 2;
  showToast(`Simplified to ${newLatLngs.length} points.`, 'add');
};

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
  downloadGPXFile(segments, title);

  // Remove edit mode UI, reset
  editablePolyline.remove();
  editablePolyline = null;
  isEditing = false;
  resetEditModeUI();
  // Optionally: render the new route as main polyline
  if (trailPolyline) map.removeLayer(trailPolyline);
  trailPolyline = L.polyline(segments[0].map(p => [p.lat, p.lng]), { color: '#007bff', weight: 3, opacity: 0.7 }).addTo(map);
};

// --- Hide/reset all Edit Route toolbar UI (shared by Exit Edit and Save as New Route) ---
function resetEditModeUI() {
  setBulkMode(null);
  setCropMode(false);
  setSplitMode(false);
  bulkAddBtn.style.display = 'none';
  bulkDeleteBtn.style.display = 'none';
  reverseEditBtn.style.display = 'none';
  connectStartBtn.style.display = 'none';
  simplifyEditBtn.style.display = 'none';
  cropEditBtn.style.display = 'none';
  splitEditBtn.style.display = 'none';
  exitEditBtn.style.display = 'none';
  saveEditBtn.style.display = 'none';
  undoEditBtn.style.display = 'none';
  redoEditBtn.style.display = 'none';
  editBtn.style.display = '';
  editHelp.style.display = 'none';
  clearGhostsAndHighlights();
  clearCropMarkers();
  editModeHint.innerHTML = '';
}

// --- Download one or more segments as a single GPX file ---
function downloadGPXFile(segments, title) {
  const gpxString = generateMinimalGPX(segments, title);
  const blob = new Blob([gpxString], { type: "application/gpx+xml" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = `${title.replace(/\s+/g, "_")}.gpx`;
  document.body.appendChild(a); a.click(); document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

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

  
  if (uploadAnotherBtn) uploadAnotherBtn.addEventListener('click', () => {
    rideTitleDisplay.textContent = '';
    document.getElementById('ride-controls').style.display = 'none';
    resetUIToInitial();
    history.replaceState({}, document.title, window.location.pathname);
  });

  showAnalyticsBtn.addEventListener('click', showAnalyticsSection);


  // =====================================================
  // WEATHER AT RIDE TIME (Open-Meteo historical data, no API key)
  // =====================================================
  const WMO_WEATHER = {
    0:['\u2600\uFE0F','Clear'],1:['\uD83C\uDF24\uFE0F','Mostly clear'],2:['\u26C5','Partly cloudy'],3:['\u2601\uFE0F','Overcast'],
    45:['\uD83C\uDF2B\uFE0F','Fog'],48:['\uD83C\uDF2B\uFE0F','Freezing fog'],
    51:['\uD83C\uDF26\uFE0F','Light drizzle'],53:['\uD83C\uDF26\uFE0F','Drizzle'],55:['\uD83C\uDF27\uFE0F','Heavy drizzle'],
    56:['\uD83C\uDF27\uFE0F','Freezing drizzle'],57:['\uD83C\uDF27\uFE0F','Freezing drizzle'],
    61:['\uD83C\uDF26\uFE0F','Light rain'],63:['\uD83C\uDF27\uFE0F','Rain'],65:['\uD83C\uDF27\uFE0F','Heavy rain'],
    66:['\uD83C\uDF27\uFE0F','Freezing rain'],67:['\uD83C\uDF27\uFE0F','Freezing rain'],
    71:['\uD83C\uDF28\uFE0F','Light snow'],73:['\uD83C\uDF28\uFE0F','Snow'],75:['\u2744\uFE0F','Heavy snow'],77:['\uD83C\uDF28\uFE0F','Snow grains'],
    80:['\uD83C\uDF26\uFE0F','Light showers'],81:['\uD83C\uDF27\uFE0F','Showers'],82:['\u26C8\uFE0F','Heavy showers'],
    85:['\uD83C\uDF28\uFE0F','Snow showers'],86:['\u2744\uFE0F','Snow showers'],
    95:['\u26C8\uFE0F','Thunderstorm'],96:['\u26C8\uFE0F','Thunderstorm'],99:['\u26C8\uFE0F','Thunderstorm']
  };

  async function fetchAndShowWeather() {
    const el = document.getElementById('weather');
    if (!el) return;
    if (!points.length || !(points[0].time instanceof Date) || isNaN(points[0].time)) {
      el.textContent = '\u2013';
      return;
    }
    el.textContent = 'Checking\u2026';
    try {
      const p = points[0];
      const d = p.time;
      const dateStr = d.toISOString().slice(0, 10);
      const ageDays = (Date.now() - d.getTime()) / 86400000;
      // Archive API lags ~5 days behind; recent rides use the forecast API's recent-past window.
      const base = ageDays > 5.5
        ? 'https://archive-api.open-meteo.com/v1/archive'
        : 'https://api.open-meteo.com/v1/forecast';
      const url = `${base}?latitude=${p.lat.toFixed(4)}&longitude=${p.lng.toFixed(4)}` +
        `&start_date=${dateStr}&end_date=${dateStr}` +
        `&hourly=temperature_2m,precipitation,weather_code,wind_speed_10m&timezone=UTC`;
      const resp = await fetch(url);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const data = await resp.json();
      const times = data?.hourly?.time || [];
      const targetHour = d.toISOString().slice(0, 13); // e.g. "2026-06-28T09"
      let idx = times.findIndex(t => t.slice(0, 13) === targetHour);
      if (idx === -1) idx = 0;
      const temp = data.hourly.temperature_2m?.[idx];
      const wind = data.hourly.wind_speed_10m?.[idx];
      const precip = data.hourly.precipitation?.[idx];
      const code = data.hourly.weather_code?.[idx];
      if (!Number.isFinite(temp)) throw new Error('no data');
      const [emoji, desc] = WMO_WEATHER[code] || ['\uD83C\uDF24\uFE0F', ''];
      let text = `${emoji} ${temp.toFixed(0)}\u00B0C${desc ? ', ' + desc.toLowerCase() : ''}`;
      if (Number.isFinite(wind)) text += `, wind ${wind.toFixed(0)} km/h`;
      if (Number.isFinite(precip) && precip >= 0.2) text += `, ${precip.toFixed(1)} mm rain that hour`;
      el.textContent = text;
    } catch (err) {
      el.textContent = 'unavailable';
    }
  }

  // =====================================================
  // SECTION 6.5: EXPORTS - RIDE CARD (PNG) & REPLAY VIDEO
  // (map-backed via CARTO dark basemap © OpenStreetMap © CARTO)
  // =====================================================

  // [export-helpers-start]
  // --- Web Mercator helpers (0..1 world coordinates) ---
  function mercX(lng) { return (lng + 180) / 360; }
  function mercY(lat) {
    const s = Math.sin(Math.max(-85.05, Math.min(85.05, lat)) * Math.PI / 180);
    return 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
  }

  // Pick a zoom that fits the route inside the box (with padding) and return
  // a project(point) -> [canvasX, canvasY] function anchored to that view.
  function fitMapView(pts, boxX, boxY, boxW, boxH, maxZoom = 16) {
    let minX = 1, maxX = 0, minY = 1, maxY = 0;
    for (const p of pts) {
      const x = mercX(p.lng), y = mercY(p.lat);
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
    const pad = 0.12;
    const usableW = boxW * (1 - pad * 2), usableH = boxH * (1 - pad * 2);
    let z = maxZoom;
    while (z > 3) {
      const world = 256 * Math.pow(2, z);
      if ((maxX - minX) * world <= usableW && (maxY - minY) * world <= usableH) break;
      z--;
    }
    const world = 256 * Math.pow(2, z);
    const cxWorld = (minX + maxX) / 2 * world;
    const cyWorld = (minY + maxY) / 2 * world;
    const originX = cxWorld - (boxX + boxW / 2); // world px at canvas x=0
    const originY = cyWorld - (boxY + boxH / 2);
    const project = p => [mercX(p.lng) * world - originX, mercY(p.lat) * world - originY];
    return { z, world, originX, originY, project };
  }

  // Legacy projection (equirectangular, aspect-fit) - used when map tiles fail.
  function fitRouteProjection(pts, boxX, boxY, boxW, boxH) {
    let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
    for (const p of pts) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    const midLat = (minLat + maxLat) / 2;
    const lngScale = Math.cos(midLat * Math.PI / 180);
    const unitW = Math.max((maxLng - minLng) * lngScale, 1e-9);
    const unitH = Math.max(maxLat - minLat, 1e-9);
    const scale = Math.min(boxW / unitW, boxH / unitH) * 0.86;
    const drawW = unitW * scale, drawH = unitH * scale;
    const offX = boxX + (boxW - drawW) / 2;
    const offY = boxY + (boxH - drawH) / 2;
    return p => [
      offX + ((p.lng - minLng) * lngScale / unitW) * drawW,
      offY + ((maxLat - p.lat) / unitH) * drawH
    ];
  }

  // Draw map tiles for a view into the region [rx, ry, rw, rh] of the canvas.
  // Returns true if at least ~70% of tiles rendered. `loadFn` is injectable for tests.
  async function drawMapTiles(ctx, view, rx, ry, rw, rh, loadFn) {
    const load = loadFn || function loadTileImage(url) {
      return new Promise((resolve, reject) => {
        const img = new Image();
        img.crossOrigin = 'anonymous';
        const timer = setTimeout(() => reject(new Error('tile timeout')), 8000);
        img.onload = () => { clearTimeout(timer); resolve(img); };
        img.onerror = () => { clearTimeout(timer); reject(new Error('tile error')); };
        img.src = url;
      });
    };
    const { z, originX, originY } = view;
    const n = Math.pow(2, z);
    const subs = ['a', 'b', 'c', 'd'];
    const tx0 = Math.floor((originX + rx) / 256), tx1 = Math.floor((originX + rx + rw) / 256);
    const ty0 = Math.floor((originY + ry) / 256), ty1 = Math.floor((originY + ry + rh) / 256);
    const jobs = [];
    let total = 0, okCount = 0;
    for (let tx = tx0; tx <= tx1; tx++) {
      for (let ty = ty0; ty <= ty1; ty++) {
        if (ty < 0 || ty >= n) continue;
        const wrappedX = ((tx % n) + n) % n;
        const sub = subs[(Math.abs(tx) + Math.abs(ty)) % subs.length];
        const url = `https://${sub}.basemaps.cartocdn.com/dark_all/${z}/${wrappedX}/${ty}@2x.png`;
        const dx = tx * 256 - originX, dy = ty * 256 - originY;
        total++;
        jobs.push(
          load(url)
            .then(img => { ctx.drawImage(img, dx, dy, 256, 256); okCount++; })
            .catch(() => {})
        );
      }
    }
    if (total === 0 || total > 120) return false; // sanity cap
    await Promise.allSettled(jobs);
    return okCount / total >= 0.7;
  }

  function traceRoute(ctx, pts, project) {
    ctx.beginPath();
    pts.forEach((p, i) => {
      const [x, y] = project(p);
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    });
  }

  function strokeRoute(ctx, pts, project, W) {
    ctx.save();
    traceRoute(ctx, pts, project);
    ctx.strokeStyle = 'rgba(100,255,218,0.30)';
    ctx.lineWidth = Math.max(9, W * 0.010);
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.shadowColor = '#64ffda';
    ctx.shadowBlur = W * 0.016;
    ctx.stroke();
    ctx.restore();
    ctx.save();
    traceRoute(ctx, pts, project);
    ctx.strokeStyle = '#64ffda';
    ctx.lineWidth = Math.max(3.5, W * 0.0042);
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.stroke();
    ctx.restore();
  }

  function drawDot(ctx, x, y, r, color, glow) {
    ctx.save();
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.shadowColor = glow || color;
    ctx.shadowBlur = r * 2.5;
    ctx.fill();
    ctx.restore();
    ctx.save();
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.strokeStyle = '#0a192f';
    ctx.lineWidth = Math.max(2, r * 0.35);
    ctx.stroke();
    ctx.restore();
  }

  function roundRectPath(c, x, y, w, h, r) {
    c.beginPath();
    c.moveTo(x + r, y);
    c.arcTo(x + w, y, x + w, y + h, r);
    c.arcTo(x + w, y + h, x, y + h, r);
    c.arcTo(x, y + h, x, y, r);
    c.arcTo(x, y, x + w, y, r);
    c.closePath();
  }

  function drawAttribution(ctx, x, y) {
    ctx.save();
    ctx.textAlign = 'right';
    ctx.fillStyle = 'rgba(255,255,255,0.55)';
    ctx.font = '400 15px "Segoe UI", Arial, sans-serif';
    ctx.fillText('© OpenStreetMap contributors © CARTO', x, y);
    ctx.restore();
  }

  // Draw the full shareable ride card (async: fetches map tiles, falls back to styled line).
  // data = { title, dateStr, stats, points }; loadFn only used by tests.
  async function drawRideCard(ctx, W, H, data, loadFn) {
    ctx.fillStyle = '#0a192f';
    ctx.fillRect(0, 0, W, H);
    const vg = ctx.createRadialGradient(W / 2, H * 0.42, H * 0.1, W / 2, H * 0.42, H * 0.85);
    vg.addColorStop(0, 'rgba(0,123,255,0.10)');
    vg.addColorStop(1, 'rgba(0,0,0,0.25)');
    ctx.fillStyle = vg;
    ctx.fillRect(0, 0, W, H);

    const M = Math.round(W * 0.074);

    // Brand
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = '#64ffda';
    ctx.font = `600 ${Math.round(W * 0.024)}px "Segoe UI", Arial, sans-serif`;
    ctx.fillText('M E M O R Y   L A N E S', M, M + W * 0.01);
    ctx.fillStyle = '#a8b7c8';
    ctx.font = `400 ${Math.round(W * 0.019)}px "Segoe UI", Arial, sans-serif`;
    ctx.fillText('journal your ride!', M, M + W * 0.042);

    // Title + date
    ctx.fillStyle = '#ffffff';
    let titleSize = Math.round(W * 0.062);
    ctx.font = `700 ${titleSize}px "Segoe UI", Arial, sans-serif`;
    while (ctx.measureText(data.title).width > W - 2 * M && titleSize > 22) {
      titleSize -= 2;
      ctx.font = `700 ${titleSize}px "Segoe UI", Arial, sans-serif`;
    }
    ctx.fillText(data.title, M, M + W * 0.125);
    ctx.fillStyle = '#8fa4bd';
    ctx.font = `400 ${Math.round(W * 0.026)}px "Segoe UI", Arial, sans-serif`;
    ctx.fillText(data.dateStr, M, M + W * 0.168);

    // Route panel (rounded, map-filled)
    const routeTop = M + W * 0.21;
    const statsBandH = H * 0.16;
    const box = { x: M, y: routeTop, w: W - 2 * M, h: H - routeTop - statsBandH - M * 1.1 };
    const radius = Math.round(W * 0.024);

    const view = fitMapView(data.points, box.x, box.y, box.w, box.h, 16);
    ctx.save();
    roundRectPath(ctx, box.x, box.y, box.w, box.h, radius);
    ctx.clip();
    ctx.fillStyle = '#0e1a2b';
    ctx.fillRect(box.x, box.y, box.w, box.h);
    const tilesOk = await drawMapTiles(ctx, view, box.x, box.y, box.w, box.h, loadFn);
    let project = view.project;
    if (tilesOk) {
      // Gentle tint so the neon route pops and the card stays on-brand
      ctx.fillStyle = 'rgba(10,25,47,0.22)';
      ctx.fillRect(box.x, box.y, box.w, box.h);
    } else {
      project = fitRouteProjection(data.points, box.x, box.y, box.w, box.h);
    }

    strokeRoute(ctx, data.points, project, W);
    const [sx, sy] = project(data.points[0]);
    const [ex, ey] = project(data.points[data.points.length - 1]);
    drawDot(ctx, sx, sy, Math.max(7, W * 0.009), '#21c821');
    drawDot(ctx, ex, ey, Math.max(7, W * 0.009), '#ff6384');
    if (tilesOk) drawAttribution(ctx, box.x + box.w - 12, box.y + box.h - 12);
    ctx.restore();

    // Panel border
    ctx.save();
    roundRectPath(ctx, box.x, box.y, box.w, box.h, radius);
    ctx.strokeStyle = 'rgba(100,255,218,0.35)';
    ctx.lineWidth = 3;
    ctx.stroke();
    ctx.restore();

    // Stats band
    const bandY = H - statsBandH - M * 0.55;
    ctx.strokeStyle = 'rgba(100,255,218,0.25)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(M, bandY);
    ctx.lineTo(W - M, bandY);
    ctx.stroke();

    const n = data.stats.length;
    const cellW = (W - 2 * M) / n;
    data.stats.forEach((s, i) => {
      const cx = M + cellW * i + cellW / 2;
      ctx.textAlign = 'center';
      ctx.fillStyle = '#ffffff';
      ctx.font = `700 ${Math.round(W * 0.040)}px "Segoe UI", Arial, sans-serif`;
      ctx.fillText(s.value, cx, bandY + statsBandH * 0.48);
      ctx.fillStyle = '#8fa4bd';
      ctx.font = `500 ${Math.round(W * 0.019)}px "Segoe UI", Arial, sans-serif`;
      ctx.fillText(s.label.toUpperCase(), cx, bandY + statsBandH * 0.75);
    });
    ctx.textAlign = 'left';
  }
  // [export-helpers-end]

  function currentRideTitle() {
    const typed = document.getElementById('ride-title')?.value.trim();
    if (typed) return typed;
    const m = (rideTitleDisplay.textContent || '').match(/[“"](.+)[”"]/);
    if (m) return m[1];
    return 'My Ride';
  }

  function currentRideStats() {
    const maxSpeed = speedData.reduce((mx, v) => (Number.isFinite(v) && v > mx ? v : mx), 0);
    return [
      { label: 'Distance', value: distanceEl.textContent },
      { label: 'Ride Time', value: rideTimeEl.textContent },
      { label: 'Elev Gain', value: elevationEl.textContent },
      { label: 'Max Speed', value: `${maxSpeed.toFixed(0)} km/h` }
    ];
  }

  function downloadBlob(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  }

  function safeFilename(name) {
    return name.replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '_') || 'ride';
  }

  // ---- RIDE CARD (Download Summary) ----
  summaryBtn.addEventListener('click', async () => {
    if (!points.length) { showToast('Load a ride first.', 'info'); return; }
    if (summaryBtn.disabled) return;
    const originalLabel = summaryBtn.textContent;
    summaryBtn.disabled = true;
    summaryBtn.textContent = 'Preparing…';
    try {
      const W = 1080, H = 1350;
      const canvas = document.createElement('canvas');
      canvas.width = W;
      canvas.height = H;
      const ctx = canvas.getContext('2d');
      await drawRideCard(ctx, W, H, {
        title: currentRideTitle(),
        dateStr: points[0].time.toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' }),
        stats: currentRideStats(),
        points
      });
      canvas.toBlob(blob => {
        if (!blob) { showToast('Could not create the ride card.', 'delete'); return; }
        downloadBlob(blob, `${safeFilename(currentRideTitle())}_ride_card.png`);
        showToast('Ride card downloaded!', 'add');
      }, 'image/png');
    } catch (err) {
      console.error('Ride card export failed:', err);
      showToast('Could not create the ride card.', 'delete');
    } finally {
      summaryBtn.disabled = false;
      summaryBtn.textContent = originalLabel;
    }
  });

  // ---- REPLAY VIDEO (Export Video) ----
  videoBtn.addEventListener('click', async () => {
    if (!points.length) { showToast('Load a ride first.', 'info'); return; }
    if (videoBtn.disabled) return;
    if (typeof MediaRecorder === 'undefined' || !HTMLCanvasElement.prototype.captureStream) {
      showToast("Video export isn't supported in this browser.", 'delete');
      return;
    }
    const mime = [
      'video/mp4;codecs=avc1',
      'video/webm;codecs=vp9',
      'video/webm;codecs=vp8',
      'video/webm'
    ].find(t => MediaRecorder.isTypeSupported(t));
    if (!mime) {
      showToast("Video export isn't supported in this browser.", 'delete');
      return;
    }
    const ext = mime.startsWith('video/mp4') ? 'mp4' : 'webm';

    const originalLabel = videoBtn.textContent;
    videoBtn.disabled = true;
    videoBtn.textContent = 'Preparing map…';

    const W = 1280, H = 720;
    const canvas = document.createElement('canvas');
    canvas.width = W;
    canvas.height = H;
    const ctx = canvas.getContext('2d');

    const title = currentRideTitle();
    const dateStr = points[0].time.toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' });
    const lastIdx = points.length - 1;
    const DURATION_MS = Math.min(30000, Math.max(12000, points.length * 25));

    // Route fits the right/centre area; map tiles fill the whole frame behind everything.
    const view = fitMapView(points, W * 0.30, H * 0.15, W * 0.64, H * 0.64, 16);

    // Pre-render the static background once (map + tint + header scrims)
    const bg = document.createElement('canvas');
    bg.width = W; bg.height = H;
    const bctx = bg.getContext('2d');
    bctx.fillStyle = '#0a192f';
    bctx.fillRect(0, 0, W, H);
    let tilesOk = false;
    try {
      tilesOk = await drawMapTiles(bctx, view, 0, 0, W, H);
    } catch (_) { tilesOk = false; }
    let project = view.project;
    if (tilesOk) {
      bctx.fillStyle = 'rgba(10,25,47,0.30)';
      bctx.fillRect(0, 0, W, H);
    } else {
      project = fitRouteProjection(points, W * 0.30, H * 0.15, W * 0.64, H * 0.64);
    }
    // Scrims for text legibility
    let g = bctx.createLinearGradient(0, 0, 0, 150);
    g.addColorStop(0, 'rgba(10,25,47,0.85)');
    g.addColorStop(1, 'rgba(10,25,47,0)');
    bctx.fillStyle = g;
    bctx.fillRect(0, 0, W, 150);
    g = bctx.createLinearGradient(0, H - 90, 0, H);
    g.addColorStop(0, 'rgba(10,25,47,0)');
    g.addColorStop(1, 'rgba(10,25,47,0.85)');
    bctx.fillStyle = g;
    bctx.fillRect(0, H - 90, W, 90);

    function drawFrame(t) { // t in [0,1]
      const f = Math.min(lastIdx, t * lastIdx);
      const idx = Math.floor(f);
      const frac = f - idx;
      const p0 = points[idx], p1 = points[Math.min(idx + 1, lastIdx)];
      const [ax, ay] = project(p0), [bx, by] = project(p1);
      const cx = ax + (bx - ax) * frac, cy = ay + (by - ay) * frac;

      ctx.drawImage(bg, 0, 0);

      // Header
      ctx.textAlign = 'left';
      ctx.fillStyle = '#64ffda';
      ctx.font = '600 20px "Segoe UI", Arial, sans-serif';
      ctx.fillText('MEMORY LANES', 40, 48);
      ctx.fillStyle = '#ffffff';
      ctx.font = '700 34px "Segoe UI", Arial, sans-serif';
      ctx.fillText(title, 40, 92);
      ctx.fillStyle = '#c7d3e3';
      ctx.font = '400 20px "Segoe UI", Arial, sans-serif';
      ctx.fillText(dateStr, 40, 122);

      // Full route, dim
      ctx.save();
      traceRoute(ctx, points, project);
      ctx.strokeStyle = 'rgba(255,255,255,0.28)';
      ctx.lineWidth = 4;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.stroke();
      ctx.restore();

      // Progress route, bright
      ctx.save();
      ctx.beginPath();
      for (let i = 0; i <= idx; i++) {
        const [x, y] = project(points[i]);
        i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
      }
      ctx.lineTo(cx, cy);
      ctx.strokeStyle = '#64ffda';
      ctx.lineWidth = 5;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.shadowColor = '#64ffda';
      ctx.shadowBlur = 14;
      ctx.stroke();
      ctx.restore();

      drawDot(ctx, cx, cy, 9, '#ffffff', '#64ffda');

      // Telemetry panel
      const px = 40, py = 170, pw = 250, ph = 220;
      ctx.save();
      roundRectPath(ctx, px, py, pw, ph, 18);
      ctx.fillStyle = 'rgba(10,25,47,0.72)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(0,123,255,0.45)';
      ctx.lineWidth = 2;
      ctx.stroke();
      ctx.restore();

      const speed = speedData[idx] || 0;
      const dist = (cumulativeDistance[idx] || 0) / 1000;
      const ele = p0.ele || 0;
      ctx.fillStyle = '#ffffff';
      ctx.font = '700 52px "Segoe UI", Arial, sans-serif';
      ctx.fillText(speed.toFixed(1), px + 22, py + 74);
      ctx.fillStyle = '#8fa4bd';
      ctx.font = '500 18px "Segoe UI", Arial, sans-serif';
      ctx.fillText('KM/H', px + 22, py + 100);
      ctx.fillStyle = '#e3e8ef';
      ctx.font = '500 22px "Segoe UI", Arial, sans-serif';
      ctx.fillText(`${dist.toFixed(2)} km`, px + 22, py + 148);
      ctx.fillText(`${ele.toFixed(0)} m`, px + 22, py + 188);

      if (tilesOk) drawAttribution(ctx, W - 40, H - 66);

      // Progress bar
      const bx0 = 40, bw0 = W - 80, byy = H - 52;
      ctx.fillStyle = 'rgba(255,255,255,0.20)';
      roundRectPath(ctx, bx0, byy, bw0, 8, 4);
      ctx.fill();
      ctx.fillStyle = '#64ffda';
      roundRectPath(ctx, bx0, byy, Math.max(8, bw0 * t), 8, 4);
      ctx.fill();
    }

    // Record
    const stream = canvas.captureStream(30);
    const recorder = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 6_000_000 });
    const chunks = [];
    recorder.ondataavailable = e => { if (e.data && e.data.size) chunks.push(e.data); };

    recorder.onstop = () => {
      videoBtn.disabled = false;
      videoBtn.textContent = originalLabel;
      const blob = new Blob(chunks, { type: mime.split(';')[0] });
      if (!blob.size) { showToast('Video export failed.', 'delete'); return; }
      downloadBlob(blob, `${safeFilename(title)}_replay.${ext}`);
      showToast('Replay video downloaded!', 'add');
    };

    let startTs = null;
    function tick(ts) {
      if (startTs === null) startTs = ts;
      const elapsed = ts - startTs;
      const t = Math.min(1, elapsed / DURATION_MS);
      drawFrame(t);
      videoBtn.textContent = `Recording… ${(t * 100).toFixed(0)}%`;
      if (t < 1) {
        requestAnimationFrame(tick);
      } else {
        setTimeout(() => recorder.stop(), 300);
      }
    }

    drawFrame(0);
    recorder.start(250);
    requestAnimationFrame(tick);
    showToast(`Recording a ${(DURATION_MS / 1000).toFixed(0)}s replay, keep this tab visible.`, 'info');
  });

  // =====================================================
  // SECTION 7: GPX FILE UPLOAD
  // =====================================================
  // ---- Sample ride (synthetic demo GPX bundled with the app) ----
  document.getElementById('try-demo-btn')?.addEventListener('click', async () => {
    try {
      const resp = await fetch('assets/demo-ride.gpx');
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const gpxText = await resp.text();
      if (isEditing && exitEditBtn) exitEditBtn.onclick();
      if (window.playInterval) clearInterval(window.playInterval);
      if (marker) map.removeLayer(marker);
      if (trailPolyline) map.removeLayer(trailPolyline);
      points = []; breakPoints = []; cumulativeDistance = []; speedData = []; accelData = [];
      showUIAfterUpload(true); // hide auth prompt for the demo
      saveForm.style.display = 'none'; // demo rides cannot be saved
      rideTitleDisplay.textContent = 'Demo ride (synthetic data): explore everything, then upload your own';
      rideTitleDisplay.style.textAlign = 'center';
      document.getElementById('ride-controls').style.display = 'block';
      parseAndRenderGPX(gpxText);
      hideAnalyticsSection();
    } catch (err) {
      console.error('Demo load failed:', err);
      showToast('Could not load the sample ride.', 'delete');
    }
  });

  uploadInput.addEventListener('change', async e => {
    const file = e.target.files[0];
    if (!file) return;
    if (isEditing && exitEditBtn) exitEditBtn.onclick(); // discard any in-progress route edits
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



  // The route draws itself onto the map (ml-dash in the design canvas).
  function animateRouteDraw(polyline) {
    try {
      if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      const el = polyline && typeof polyline.getElement === 'function' ? polyline.getElement() : null;
      if (!el || typeof el.getTotalLength !== 'function') return;
      const len = el.getTotalLength();
      if (!len || !isFinite(len)) return;
      el.style.strokeDasharray = len;
      el.style.strokeDashoffset = len;
      el.classList.add('ml-route-draw');
      setTimeout(() => clearRouteDraw(polyline), 3200);
    } catch (e) { /* decorative only */ }
  }
  function clearRouteDraw(polyline) {
    try {
      const el = polyline && typeof polyline.getElement === 'function' ? polyline.getElement() : null;
      if (!el) return;
      el.classList.remove('ml-route-draw');
      el.style.strokeDasharray = '';
      el.style.strokeDashoffset = '';
    } catch (e) {}
  }

  // ========== CHARTS, ANALYTICS, PLAYBACK, SPEED BIN ==========
  function setupChart() {
    const ctx = document.getElementById('elevationChart').getContext('2d');
    if (elevationChart) elevationChart.destroy();
    const _tc = chartThemeColors();
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
            setPlayState('play');
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
            grid: { color: _tc.grid },
            ticks: { callback: v => v.toFixed(2), color: _tc.tick }
          },
          yElevation: {
            display: true,
            position: 'left',
            title: { display: true, text: 'Elevation (m)' },
            grid: { color: _tc.grid2 }, ticks: { color: _tc.tick }
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
          legend: { display: true, labels: { usePointStyle: true, pointStyle: 'line', boxWidth: 18, boxHeight: 2, font: { size: 11 }, color: _tc.tick, padding: 14 } },
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

  // =====================================================
  // ANALYTICS CHARTS v2 (driven by the Ride Coach analysis)
  // =====================================================

  // --- Corner speed vs radius, with iso-g reference curves ---
// Theme-aware chart colors: canvas can't read CSS vars, so resolve them at draw time.
function chartThemeColors() {
  const cs = getComputedStyle(document.documentElement);
  const v = (name, fallback) => (cs.getPropertyValue(name).trim() || fallback);
  const isLight = document.documentElement.getAttribute('data-theme') === 'light'
    || (!document.documentElement.getAttribute('data-theme')
        && window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches);
  return {
    grid:  isLight ? 'rgba(15,23,42,0.10)' : 'rgba(255,255,255,0.10)',
    grid2: isLight ? 'rgba(15,23,42,0.06)' : 'rgba(255,255,255,0.06)',
    tick:  v('--color-text-muted', isLight ? '#5f6b7a' : '#8fa4bd'),
    title: v('--color-text-secondary', isLight ? '#556070' : '#c5d1e3'),
    isLight
  };
}

  function renderCornerRadiusChart(analysis, jumpToTime) {
    const _tc = chartThemeColors();
    const ctx = document.getElementById('cornerChart')?.getContext('2d');
    if (!ctx) return;
    if (window.cornerChart && typeof window.cornerChart.destroy === 'function') {
      window.cornerChart.destroy();
    }
    const corners = analysis.corners.filter(c => c.radiusM <= 320);
    const maxR = Math.max(80, ...corners.map(c => c.radiusM)) * 1.1;
    const isoLine = (gFrac, color) => {
      const data = [];
      for (let r = 10; r <= maxR; r += maxR / 60) {
        data.push({ x: r, y: 3.6 * Math.sqrt(gFrac * 9.81 * r) });
      }
      return {
        label: `${gFrac.toFixed(1)} g`, data, type: 'line',
        borderColor: color, borderWidth: 1.5, borderDash: [6, 6],
        pointRadius: 0, fill: false, order: 10
      };
    };
    window.cornerChart = new Chart(ctx, {
      type: 'scatter',
      data: {
        datasets: [
          {
            label: 'Corners', order: 1,
            data: corners.map(c => ({ x: c.radiusM, y: c.apexKmh, t: c.tApex.getTime() })),
            pointBackgroundColor: '#64ffda', pointBorderColor: '#0a192f',
            pointRadius: 6, pointHoverRadius: 8
          },
          isoLine(0.2, 'rgba(159,180,208,0.5)'),
          isoLine(0.4, 'rgba(255,209,102,0.55)'),
          isoLine(0.6, 'rgba(255,99,132,0.55)')
        ]
      },
      options: {
        responsive: true,
        animation: false,
        interaction: { mode: 'nearest', intersect: true },
        onClick: function(evt) {
          const els = this.getElementsAtEventForMode(evt, 'nearest', { intersect: true }, true);
          if (!els.length) return;
          const dp = this.data.datasets[els[0].datasetIndex].data[els[0].index];
          if (dp && dp.t) jumpToTime(new Date(dp.t));
        },
        scales: {
          x: { type: 'linear', min: 0, title: { display: true, text: 'Corner radius (m)', color: _tc.title }, grid: { color: _tc.grid }, ticks: { color: _tc.tick } },
          y: { min: 0, title: { display: true, text: 'Apex speed (km/h)', color: _tc.title }, grid: { color: _tc.grid2 }, ticks: { color: _tc.tick } }
        },
        plugins: {
          legend: { display: true, labels: { usePointStyle: true, pointStyle: 'line', boxWidth: 18, boxHeight: 2, font: { size: 11 }, color: _tc.tick, padding: 14, filter: item => item.text !== 'Corners' } },
          tooltip: {
            callbacks: {
              label: ctx2 => ctx2.dataset.label === 'Corners'
                ? `r≈${ctx2.raw.x.toFixed(0)} m at ${ctx2.raw.y.toFixed(0)} km/h`
                : `${ctx2.dataset.label} grip line`
            }
          }
        }
      }
    });
  }

  // --- Acceleration profile with braking/drive zone bands ---
  function renderAccelProfile(analysis) {
    const _tc = chartThemeColors();
    const ctx = document.getElementById('accelChart')?.getContext('2d');
    if (!ctx) return;
    if (window.accelChart && typeof window.accelChart.destroy === 'function') {
      window.accelChart.destroy();
    }
    const zones = [
      ...analysis.brakeZones.map(z => ({ ...z, kind: 'brake' })),
      ...analysis.accelZones.map(z => ({ ...z, kind: 'drive' }))
    ];
    const zoneBands = {
      id: 'zoneBands',
      beforeDatasetsDraw(chart) {
        const { ctx: c, chartArea, scales: { x } } = chart;
        if (!chartArea) return;
        zones.forEach(z => {
          const x0 = x.getPixelForValue(z.startKm);
          const x1 = x.getPixelForValue(z.endKm);
          c.fillStyle = z.kind === 'brake' ? 'rgba(255,99,132,0.13)' : 'rgba(33,200,33,0.11)';
          c.fillRect(x0, chartArea.top, Math.max(x1 - x0, 2), chartArea.bottom - chartArea.top);
        });
      }
    };
    window.accelChart = new Chart(ctx, {
      type: 'line',
      data: {
        datasets: [
          {
            label: 'Point in Ride', type: 'scatter', order: 0,
            data: [{ x: 0, y: 0 }],
            pointRadius: 5, pointBackgroundColor: '#ffffff', borderColor: '#ffffff',
            showLine: false
          },
          {
            label: 'Acceleration (smoothed)', order: 1,
            data: analysis.accelSeries,
            borderColor: '#0168D9', borderWidth: 2, pointRadius: 0, fill: false
          }
        ]
      },
      options: {
        responsive: true,
        animation: false,
        interaction: { mode: 'nearest', intersect: false },
        scales: {
          x: { type: 'linear', title: { display: true, text: 'Distance (km)', color: _tc.title }, grid: { color: _tc.grid },
               ticks: { callback: v => v.toFixed(1), color: _tc.tick } },
          y: { title: { display: true, text: 'Acceleration (m/s²)', color: _tc.title }, grid: { color: _tc.grid2 }, ticks: { color: _tc.tick } }
        },
        plugins: {
          legend: { display: true, labels: { usePointStyle: true, pointStyle: 'line', boxWidth: 18, boxHeight: 2, font: { size: 11 }, color: _tc.tick, padding: 14, filter: item => item.text !== 'Point in Ride' } },
          tooltip: { callbacks: { label: c2 => `${c2.raw.y.toFixed(2)} m/s²` } }
        }
      },
      plugins: [zoneBands]
    });
  }

  // --- Per-ride chart insights (plain-language, computed from this ride) ---
  function renderRideInsights(analysis, hiPts) {
    let ins = null;
    try { ins = buildRideInsights(analysis, hiPts); } catch (e) { console.warn('insights failed:', e); }
    const set = (id, txt) => { const el = document.getElementById(id); if (el) el.textContent = txt || ''; };
    if (!ins) {
      ['elevation','corner','accel','grip'].forEach(k => { set('insight-'+k, ''); set('insight-'+k+'-detail', ''); });
      return;
    }
    ['elevation','corner','accel','grip'].forEach(k => {
      set('insight-' + k, ins[k].summary);
      set('insight-' + k + '-detail', ins[k].detail);
    });
  }

  // --- g-g diagram (friction circle): your grip-usage signature ---
  function renderGGChart(analysis) {
    const _tc = chartThemeColors();
    const ctx = document.getElementById('ggChart')?.getContext('2d');
    if (!ctx) return;
    if (window.ggChart && typeof window.ggChart.destroy === 'function') {
      window.ggChart.destroy();
    }
    const circle = (gFrac, color) => {
      const data = [];
      for (let a = 0; a <= 360; a += 6) {
        data.push({ x: gFrac * Math.cos(a * Math.PI / 180), y: gFrac * Math.sin(a * Math.PI / 180) });
      }
      const NAME = { '0.2': 'Relaxed', '0.4': 'Spirited', '0.6': 'Performance' };
      const key = gFrac.toFixed(1);
      return { label: NAME[key] || `${key} g`, gValue: key, data, type: 'line', borderColor: color,
               borderWidth: 1.2, borderDash: [5, 5], pointRadius: 0, fill: false, order: 10 };
    };
    const lim = 0.8;
    window.ggChart = new Chart(ctx, {
      type: 'scatter',
      data: {
        datasets: [
          {
            label: 'Samples', order: 1,
            data: analysis.ggPoints,
            pointBackgroundColor: 'rgba(100,255,218,0.45)', pointBorderColor: 'transparent',
            pointRadius: 2.4
          },
          circle(0.2, 'rgba(159,180,208,0.45)'),
          circle(0.4, 'rgba(255,209,102,0.5)'),
          circle(0.6, 'rgba(255,99,132,0.5)')
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        aspectRatio: 1,
        animation: false,
        scales: {
          x: { min: -lim, max: lim, title: { display: true, text: 'Lateral g  (left ‹ › right)', color: _tc.title }, grid: { color: _tc.grid }, ticks: { color: _tc.tick } },
          y: { min: -lim, max: lim, title: { display: true, text: 'Longitudinal g (brake ‹ › drive)', color: _tc.title }, grid: { color: _tc.grid2 }, ticks: { color: _tc.tick } }
        },
        plugins: {
          legend: { display: true, labels: { usePointStyle: true, pointStyle: 'line', boxWidth: 18, boxHeight: 2, font: { size: 11 }, color: _tc.tick, padding: 14, filter: item => item.text !== 'Samples' } },
          tooltip: {
            enabled: true,
            callbacks: {
              label: (ctx) => {
                const ds = ctx.dataset;
                if (ds.gValue) return `${ds.label}: ${ds.gValue} g`;
                return `lat ${ctx.parsed.x.toFixed(2)} g, long ${ctx.parsed.y.toFixed(2)} g`;
              }
            }
          }
        }
      }
    });
  }

  // ========== SPEED FILTER (map highlight) ==========
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
    if (selectedSpeedBins.size === 0) return;
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
  }

  // ========== TIMELINE / PLAYBACK ==========
  window.jumpToPlaybackIndex = function(idx) {
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      setPlayState('play');
    }
    document.getElementById('replay-slider').value = idx;
    window.fracIndex = idx;
    updatePlayback(idx);
  }

  window.updatePlayback = idx => {
    clearRouteDraw(trailPolyline);
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
      // (cursor handled below)
    }

    slider.value = idx;
    setScrubberFill(slider);
    document.getElementById('telemetry-elevation').textContent = `${p.ele.toFixed(0)} m`;
    document.getElementById('telemetry-distance').textContent = `${distKm} km`;
    document.getElementById('telemetry-speed').textContent = `${speedData[idx].toFixed(1)} km/h`;

    const posAccelDs = window.accelChart?.data?.datasets?.find(d => d.label === 'Point in Ride');
    if (posAccelDs) {
      posAccelDs.data[0] = { x: parseFloat(distKm), y: accelData[idx] || 0 };
      window.accelChart.update('none');
    }
  };

  playBtn.addEventListener('click', () => {
    if (!points.length) return;
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      setPlayState('play');
      return;
    }
    window.fracIndex = Number(slider.value);
    // If we're at (or past) the end, restart the replay from the beginning
    if (window.fracIndex >= points.length - 1) {
      window.fracIndex = 0;
      updatePlayback(0);
    }
    setPlayState('pause');
    const mult = parseFloat(speedSel.value) || 1;
    window.playInterval = setInterval(() => {
      window.fracIndex += mult;
      const idx = Math.floor(window.fracIndex);
      if (idx >= points.length) {
        clearInterval(window.playInterval);
        window.playInterval = null;
        setPlayState('replay');
        return;
      }
      updatePlayback(idx);
    }, FRAME_DELAY_MS);
  });

  slider.addEventListener('input', () => {
    setScrubberFill(slider);
    if (window.playInterval) {
      clearInterval(window.playInterval);
      window.playInterval = null;
      setPlayState('play');
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
    statusEl.textContent = `Login failed: ${error.message}`;
    return;
  }

  // Clear old messages
  document.getElementById('save-status').textContent = '';
  statusEl.textContent = 'Login successful!';
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
  statusEl.textContent = 'Login successful!';
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
  if (saveBtn.disabled) return;
  const title = document.getElementById('ride-title').value.trim();
  const statusEl = document.getElementById('save-status');
  statusEl.textContent = ''; // Clear old

  // Check title
  if (!title) {
    showToast('Please enter a ride title.', "info");
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
    showToast('You must be logged in to save a ride.', "delete");
    return;
  }

  // Check GPX file
  const file = uploadInput.files[0];
  if (!file) {
    showToast('No GPX file selected.', "info");
    return;
  }

  // File validation for security
  const validTypes = ['application/gpx+xml', 'application/xml', 'text/xml'];
  if (!validTypes.includes(file.type) && !file.name.endsWith('.gpx')) {
    showToast('Invalid file type. Please upload a .gpx file.', "delete");
    return;
  }
  if (file.size > 5 * 1024 * 1024) { // 5 MB limit
    showToast('GPX file is too large (max 5MB).', "delete");
    return;
  }

  // Lock the button while saving so double clicks don't create duplicates
  saveBtn.disabled = true;
  const originalSaveLabel = saveBtn.textContent;
  saveBtn.textContent = 'Saving…';
  const unlockSave = () => {
    saveBtn.disabled = false;
    saveBtn.textContent = originalSaveLabel;
  };

  // Upload to Supabase Storage
  const ext      = file.name.split('.').pop();
  const stamp    = Date.now();
  const filePath = `${user.id}/${stamp}.${ext}`;
  const { data: uploadData, error: uploadErr } = await supabase
    .storage
    .from('gpx-files')
    .upload(filePath, file);
  if (uploadErr) {
    showToast(`GPX upload failed: ${uploadErr.message}`, "delete");
    unlockSave();
    return;
  }

  // Prepare data for insertion
  const distance_km  = parseFloat(distanceEl.textContent);
  const duration_min = parseFloat(rideTimeEl.textContent.split('h')[0]) * 60 +
                       (parseFloat(rideTimeEl.textContent.split('h')[1]) || 0);
  const elevation_m  = parseFloat(elevationEl.textContent);
  const ride_date = points[0].time.toISOString();
  const basePayload = {
    title,
    user_id:     user.id,
    distance_km,
    duration_min,
    elevation_m,
    ride_date,
    gpx_path:    uploadData.path
  };
  let { data: insertData, error: insertErr } = await supabase
    .from('ride_logs')
    .insert(lastSkillsSummary ? { ...basePayload, skills: lastSkillsSummary } : basePayload)
    .select('*')
    .single();
  if (insertErr && lastSkillsSummary && /skills/i.test(insertErr.message || '')) {
    // skills column not migrated yet: save the ride anyway, without skills
    ({ data: insertData, error: insertErr } = await supabase
      .from('ride_logs')
      .insert(basePayload)
      .select('*')
      .single());
  }
  if (insertErr) {
    // The GPX already uploaded but the ride record failed to save. Remove the
    // orphaned file so storage does not accumulate files with no matching ride.
    try {
      await supabase.storage.from('gpx-files').remove([uploadData.path]);
    } catch (cleanupErr) {
      console.warn('Could not remove orphaned GPX after failed save:', cleanupErr);
    }
    showToast(`Save failed: ${insertErr.message}`, "delete");
    unlockSave();
    return;
  }

  unlockSave();
  showToast('Ride saved! You can now add moments or open Logs from the top nav.', "add");
  showFireworks();
  saveForm.style.display = 'none';

  // Promote the current page into a saved-ride view immediately,
  // so Moments can save without forcing a dashboard round-trip.
  if (insertData?.id) {
    currentRideRow = insertData;
    history.replaceState({}, document.title, `${window.location.pathname}?ride=${insertData.id}`);

    rideTitleDisplay.textContent = insertData.title
      ? `Viewing: “${insertData.title}”`
      : `Viewing Saved Ride`;
    rideTitleDisplay.style.color = '';
    rideTitleDisplay.style.textAlign = 'center';
    document.getElementById('ride-controls').style.display = 'block';

    rideMoments = Array.isArray(insertData.moments) ? insertData.moments : [];
    if (momentsSection) {
      momentsSection.style.display = 'block';
      momentsTools.style.display = 'block';
      toggleMomentsBtn.textContent = 'Hide Moments & Journal';
      renderMoments();
    }

    if (typeof refreshShareButtons === 'function') {
      refreshShareButtons(insertData);
    }
  }
  
});



// ========== INIT ==========
resetUIToInitial();


// ========== SKILLS STORAGE & REPEAT-CORNER RECOGNITION ==========
let lastSkillsSummary = null;

async function storeSkillsForCurrentRide(summary) {
  if (!summary) return;
  const p = new URLSearchParams(window.location.search);
  const rideId = p.get('ride');
  if (!rideId) return; // fresh uploads store at save time instead
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;
  const { error } = await supabase
    .from('ride_logs')
    .update({ skills: summary })
    .eq('id', rideId)
    .eq('user_id', user.id);
  if (error) console.warn('Skill storage skipped (run supabase-skills-setup.sql to enable trends):', error.message);
}

// Average scores across the rider's recent scored rides (for trend-aware coaching)
async function fetchRecentAvgScores(excludeId) {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return null;
    let q = supabase
      .from('ride_logs')
      .select('skills, ride_date')
      .eq('user_id', user.id)
      .not('skills', 'is', null)
      .order('ride_date', { ascending: false })
      .limit(8);
    if (excludeId) q = q.neq('id', excludeId);
    const { data, error } = await q;
    if (error || !data || !data.length) return null;
    const sums = {}, counts = {};
    data.forEach(r => {
      Object.entries(r.skills?.scores || {}).forEach(([k, v]) => {
        if (Number.isFinite(v)) { sums[k] = (sums[k] || 0) + v; counts[k] = (counts[k] || 0) + 1; }
      });
    });
    const avg = {};
    Object.keys(sums).forEach(k => { avg[k] = sums[k] / counts[k]; });
    return Object.keys(avg).length ? avg : null;
  } catch (_) { return null; }
}

function havMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000, toR = Math.PI / 180;
  const dLat = (lat2 - lat1) * toR, dLng = (lng2 - lng1) * toR;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * toR) * Math.cos(lat2 * toR) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
function headingDiff(a, b) {
  let d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
}

async function enhanceRepeatCorners(analysis) {
  try {
    const p = new URLSearchParams(window.location.search);
    const rideId = p.get('ride');
    if (!rideId) return;
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;
    const { data: rows, error } = await supabase
      .from('ride_logs')
      .select('id, ride_date, skills')
      .eq('user_id', user.id)
      .neq('id', rideId)
      .not('skills', 'is', null)
      .limit(150);
    if (error || !rows || !rows.length) return;
    const past = [];
    rows.forEach(r => (r.skills?.corners || []).forEach(c => past.push(c)));
    if (!past.length) return;
    const top = [...analysis.corners].sort((a, b) => b.maxLatG - a.maxLatG).slice(0, 10);
    document.querySelectorAll('#rider-skills-content .corner-card').forEach((card, i) => {
      const c = top[i];
      if (!c) return;
      const matches = past.filter(pc =>
        havMeters(c.apexLat, c.apexLng, pc.la, pc.ln) < 35 &&
        headingDiff(c.apexHeadingDeg, pc.hd) < 60
      );
      if (!matches.length) return;
      const bestPast = Math.max(...matches.map(m => m.ak));
      const cur = Math.round(c.apexKmh);
      const cmp = cur > bestPast ? 'a new best!' : `best ${bestPast} km/h`;
      const div = document.createElement('div');
      div.className = 'corner-history';
      div.textContent = `You have ridden this corner ${matches.length + 1} times. Apex today ${cur} km/h, ${cmp}`;
      card.querySelector('.corner-main').appendChild(div);
    });
  } catch (e) {
    console.warn('Repeat-corner check skipped:', e);
  }
}

// ========== SHARE RIDE (public read-only links) ==========
const shareRideBtn = document.getElementById('share-ride-btn');
const unshareRideBtn = document.getElementById('unshare-ride-btn');
const openJournalBtn = document.getElementById('open-journal');

if (openJournalBtn) {
  openJournalBtn.addEventListener('click', () => { window.location.href = 'journal.html'; });
}

function shareLinkFor(token) {
  return `${window.location.origin}${window.location.pathname}?share=${token}`;
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch (_) {
    window.prompt('Copy this share link:', text);
    return false;
  }
}

function refreshShareButtons(ride) {
  if (!shareRideBtn) return;
  if (ride && ride.is_public) {
    shareRideBtn.textContent = '\uD83D\uDD17 Copy Share Link';
    shareRideBtn.style.display = '';
    unshareRideBtn.style.display = '';
  } else {
    shareRideBtn.textContent = '\uD83D\uDD17 Share Ride';
    shareRideBtn.style.display = '';
    unshareRideBtn.style.display = 'none';
  }
}

let currentRideRow = null; // the ride being viewed, when the owner loaded it

if (shareRideBtn) {
  shareRideBtn.addEventListener('click', async () => {
    if (!currentRideRow) return;
    if (currentRideRow.share_token === undefined) {
      showToast('Sharing needs a one-time database setup \u2014 see supabase-share-setup.sql in the repo.', 'info');
      return;
    }
    if (!currentRideRow.is_public) {
      const { data, error } = await supabase
        .from('ride_logs')
        .update({ is_public: true })
        .eq('id', currentRideRow.id)
        .select('is_public, share_token')
        .single();
      if (error || !data) {
        showToast(`\u274C Could not share: ${error?.message || 'unknown error'}`, 'delete');
        return;
      }
      currentRideRow.is_public = data.is_public;
      currentRideRow.share_token = data.share_token;
      refreshShareButtons(currentRideRow);
      const copied = await copyText(shareLinkFor(currentRideRow.share_token));
      showToast(copied ? '\u2705 Ride shared \u2014 link copied!' : '\u2705 Ride shared!', 'add');
    } else {
      const copied = await copyText(shareLinkFor(currentRideRow.share_token));
      showToast(copied ? '\u2705 Share link copied!' : 'Here is your link.', 'add');
    }
  });
}

if (unshareRideBtn) {
  unshareRideBtn.addEventListener('click', async () => {
    if (!currentRideRow || !currentRideRow.is_public) return;
    if (!confirm('Stop sharing this ride? Existing links will stop working.')) return;
    const { error } = await supabase
      .from('ride_logs')
      .update({ is_public: false })
      .eq('id', currentRideRow.id);
    if (error) {
      showToast(`\u274C Could not unshare: ${error.message}`, 'delete');
      return;
    }
    currentRideRow.is_public = false;
    refreshShareButtons(currentRideRow);
    showToast('Ride is private again.', 'add');
  });
}

// ========== READ-ONLY MOMENTS (for shared rides) ==========
function renderSharedMoments(moments) {
  if (!Array.isArray(moments) || !moments.length) {
    momentsSection.style.display = 'none';
    return;
  }
  momentsSection.style.display = 'block';
  toggleMomentsBtn.style.display = 'none';
  momentsTools.style.display = 'block';
  addMomentBtn.style.display = 'none';
  momentsList.innerHTML = moments.map(m => `
    <div class="moment-entry">
      <div style="display:flex; gap:1rem; align-items:center; margin-bottom:0.3rem;">
        <span style="font-size:1.15em;">\uD83D\uDCCD</span>
        <span>
          <strong>${escapeHtml(m.title) || 'Moment'}</strong><br>
          ${typeof m.speed === 'number' ? `${m.speed.toFixed(1)} km/h \u00B7 ` : ''}${typeof m.elevation === 'number' ? `${m.elevation.toFixed(0)} m` : ''}
        </span>
      </div>
      ${m.note ? `<div style="color:#dce7f5; margin-left:2.3rem;">${escapeHtml(m.note)}</div>` : ''}
    </div>`).join('');
  moments.forEach(m => {
    if (typeof m.lat === 'number' && typeof m.lng === 'number') {
      const marker = L.marker([m.lat, m.lng], {
        icon: L.divIcon({ className: 'moment-pin', html: '<span style="color:#8338ec;font-size:1.4em;">\u2605</span>' })
      }).addTo(map);
      marker.on('click', () => window.jumpToPlaybackIndex(Math.max(0, m.idx || 0)));
    }
  });
}

// ========== PLANNED VS ACTUAL (rides recorded via the Route Planner's "Start Ride") ==========
function sampleArr(arr, maxPoints) {
  if (arr.length <= maxPoints) return arr;
  const step = (arr.length - 1) / (maxPoints - 1);
  const out = [];
  for (let i = 0; i < maxPoints; i++) out.push(arr[Math.round(i * step)]);
  return out;
}

async function renderPlannedRouteComparison(ride) {
  if (!ride.planned_route_id) return;
  try {
    const { data: planned, error } = await supabase
      .from('planned_routes')
      .select('route')
      .eq('id', ride.planned_route_id)
      .single();
    if (error || !planned || !Array.isArray(planned.route) || planned.route.length < 2) return;

    const plannedLine = L.polyline(planned.route, {
      color: '#ffd166', weight: 4, opacity: 0.75, dashArray: '10,8'
    }).addTo(map);
    plannedLine.bringToBack();

    // Rough "route match": % of the actual ride's points that fall within
    // ON_ROUTE_M of some point on the planned line. Not a precise projection,
    // just a reflection prompt like the rest of Ride Coach's scoring.
    const ON_ROUTE_M = 60;
    const plannedSample = sampleArr(planned.route, 150);
    const actualSample = sampleArr(points, 200);
    let onRoute = 0;
    actualSample.forEach(p => {
      let minD = Infinity;
      for (const [plat, plng] of plannedSample) {
        const d = havMeters(p.lat, p.lng, plat, plng);
        if (d < minD) minD = d;
        if (minD < ON_ROUTE_M) break;
      }
      if (minD < ON_ROUTE_M) onRoute++;
    });
    const matchPct = actualSample.length ? Math.round((onRoute / actualSample.length) * 100) : null;

    const grid = document.querySelector('#summary-section .summary-grid');
    if (grid && matchPct != null) {
      const card = document.createElement('div');
      card.className = 'summary-card';
      card.innerHTML = `<div class="summary-label">Route Match</div><div class="summary-value num">${matchPct}%</div>`;
      grid.appendChild(card);
    }
  } catch (e) {
    console.warn('Planned route comparison skipped:', e);
  }
}

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
        rideTitleDisplay.textContent = "Failed to load ride. Please try another or return to dashboard.";
        rideTitleDisplay.style.color = "#ff6b6b";
        rideTitleDisplay.style.textAlign = "center";
        document.getElementById('ride-controls').style.display = 'block';
        if (rideActions) rideActions.style.display = 'none';
        return;
      }

      // All clear: update UI!
      console.log('Ride loaded:', ride);

      hideSaveForm();
      rideTitleDisplay.textContent = ride.title
        ? `Viewing: “${ride.title}”`
        : `Viewing Saved Ride`;

      rideTitleDisplay.style.color = ""; // clear any previous error color
      rideTitleDisplay.style.textAlign = "center";
      document.getElementById('ride-controls').style.display = 'block';
      if (rideActions) rideActions.style.display = 'none';

      // GPX fetch
      const { data: urlData, error: urlErr } = supabase
        .storage
        .from('gpx-files')
        .getPublicUrl(ride.gpx_path);
      if (urlErr) throw urlErr;

      const resp = await fetch(urlData.publicUrl);
      const gpxText = await resp.text();
      await parseAndRenderGPX(gpxText);
      await renderPlannedRouteComparison(ride);

      // Moments
      rideMoments = Array.isArray(ride.moments) ? ride.moments : [];
      if (momentsSection) {
        momentsSection.style.display = 'block';
        renderMoments();
      }

      showUIForSavedRide();
      hideAnalyticsSection();
      showAnalyticsBtn.style.display = 'inline-block';

      // Sharing controls - owner only
      const { data: { user: viewer } } = await supabase.auth.getUser();
      if (viewer && ride.user_id === viewer.id) {
        currentRideRow = ride;
        refreshShareButtons(ride);
      }
    } catch (err) {
      // This only triggers on actual exceptions
      rideTitleDisplay.textContent = "Error loading ride data.";
      rideTitleDisplay.style.color = "#ff6b6b";
      rideTitleDisplay.style.textAlign = "center";
      document.getElementById('ride-controls').style.display = 'block';
      if (rideActions) rideActions.style.display = 'none';
      console.error("Load error", err);
    }
  })();
}

if (params.has('share') && !params.has('ride')) {
  (async () => {
    rideTitleDisplay.textContent = '';
    try {
      const token = params.get('share');
      const { data: ride, error: shareErr } = await supabase.rpc('get_shared_ride', { token });
      if (shareErr || !ride) {
        rideTitleDisplay.textContent = '\u274C This shared ride is unavailable \u2014 the link may have been revoked.';
        rideTitleDisplay.style.color = '#ff6b6b';
        rideTitleDisplay.style.textAlign = 'center';
        document.getElementById('ride-controls').style.display = 'block';
        resetUIToInitial();
        return;
      }

      hideSaveForm();
      rideTitleDisplay.textContent = ride.title
        ? `\uD83D\uDD17 Shared Ride: \u201C${ride.title}\u201D`
        : '\uD83D\uDD17 Shared Ride';
      rideTitleDisplay.style.textAlign = 'center';
      document.getElementById('ride-controls').style.display = 'block';

      const { data: urlData } = supabase.storage.from('gpx-files').getPublicUrl(ride.gpx_path);
      const resp = await fetch(urlData.publicUrl);
      if (!resp.ok) throw new Error(`GPX fetch failed (${resp.status})`);
      const gpxText = await resp.text();
      parseAndRenderGPX(gpxText);

      showUIForSharedRide();
      renderSharedMoments(Array.isArray(ride.moments) ? ride.moments : []);
      hideAnalyticsSection();
      showAnalyticsBtn.style.display = 'inline-block';
    } catch (err) {
      console.error('Shared ride load error', err);
      rideTitleDisplay.textContent = '\u274C Error loading this shared ride.';
      rideTitleDisplay.style.color = '#ff6b6b';
      rideTitleDisplay.style.textAlign = 'center';
      document.getElementById('ride-controls').style.display = 'block';
    }
  })();
}

// Re-render charts when the theme changes so their grid/text colours follow.
  window.addEventListener('ml-themechange', () => {
    try {
      if (typeof points !== 'undefined' && points && points.length) {
        if (elevationChart) setupChart();
        if (window.lastAnalysis) {
          renderCornerRadiusChart(window.lastAnalysis, jumpToNearestTime);
          renderAccelProfile(window.lastAnalysis);
          renderGGChart(window.lastAnalysis);
        }
      }
    } catch (e) { console.warn('chart theme refresh failed:', e); }
  });

  // Header nav is plain <a href> now: it works without JS, supports keyboard,
  // middle-click and open-in-new-tab. No wiring needed.

  // === Collapsible Footer Logic ===
const toggleBtn = document.getElementById('footer-toggle');
const content = document.getElementById('footer-content');

if (toggleBtn && content) {
  toggleBtn.addEventListener('click', () => {
    const expanded = content.classList.toggle('expanded');
    toggleBtn.innerText = expanded
      ? '▼ Thanks, legend'
      : '▲ Like the vibes of the app? Tap to support the developers';
    toggleBtn.setAttribute('aria-expanded', expanded);
  });
}

// === Moments toggle ===
if (toggleMomentsBtn) toggleMomentsBtn.addEventListener('click', () => {
  const isOpen = momentsTools.style.display === 'block';
  momentsTools.style.display = isOpen ? 'none' : 'block';
  toggleMomentsBtn.textContent = isOpen ? 'Add Moments & Journal' : 'Hide Moments & Journal';
});

  
if (addMomentBtn) addMomentBtn.addEventListener('click', () => {
  if (rideMoments.length >= 5) {
    showToast('You can only save up to 5 moments for this ride.', 'info');
    return;
  }
  // Use current playback index (clamped to a valid whole index)
  const idx = Math.min(Math.max(Math.floor(window.fracIndex || 0), 0), points.length - 1);
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
// Premium, performant, robust. Triggers a short celebration at screen center.
// Requires: <canvas id="fireworks-canvas"></canvas> somewhere in HTML.

(function() {
  // --- Get and validate canvas ---
  const canvas = document.getElementById('fireworks-canvas');
  if (!canvas || !canvas.getContext) {
    console.warn('[Fireworks] Canvas element not found or unsupported.');
    window.showFireworks = () => {};
    return;
  }
  const ctx = canvas.getContext('2d');
  let running = false;      // Prevent overlapping shows

  // --- (Optional) Overlay vignette for drama ---
  function showOverlay() {
    let overlay = document.getElementById('fireworks-premium-overlay');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'fireworks-premium-overlay';
      overlay.style.cssText = `
        position:fixed;left:0;top:0;width:100vw;height:100vh;
        background:radial-gradient(ellipse at center, rgba(0,0,0,0.36) 60%, rgba(10,15,30,0.69) 100%);
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

  // --- Window resize: always keep canvas full-window size ---
  function resizeCanvas() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
  }
  window.addEventListener('resize', () => {
    if (running) resizeCanvas();
  });

  // --- Burst shape: classic, heart, star, ring ---
  function burstShape(type, n, i) {
    const theta = (i / n) * 2 * Math.PI;
    if (type === 'star') {
      // 5-point star: alternate between inner/outer points
      const points = 5, inner = 0.48, outer = 1;
      const starI = i % (points * 2);
      return (starI % 2 === 0)
        ? { r: outer, angle: (starI/2) * (2*Math.PI/points) }
        : { r: inner, angle: ((starI-1)/2) * (2*Math.PI/points) + Math.PI/points };
    }
    if (type === 'heart') {
      // Parametric heart
      return {
        r: 1.0,
        angle: theta,
        x: 16 * Math.pow(Math.sin(theta),3),
        y: -(13 * Math.cos(theta) - 5*Math.cos(2*theta) - 2*Math.cos(3*theta) - Math.cos(4*theta))
      };
    }
    // Ring or classic
    return { r: 1, angle: theta };
  }

  function randomColor() {
    // Brand palette + white/gold for premium feel
    const palette = [
      '#64ffda','#ff6384','#ffd700','#fff','#00c6ff','#8338ec','#ffac00','#19ed7d'
    ];
    return palette[Math.floor(Math.random() * palette.length)];
  }

  // --- Particle (each firework spark), includes trail ---
  function Particle(props) {
    Object.assign(this, props);
    this.history = [{x:this.x, y:this.y}]; // Store trail points
    this.maxTrail = 6 + Math.floor(Math.random()*3); // Shorter for perf
  }
  Particle.prototype.update = function(gravity, fade) {
    // Add slight path "wobble" for realism
    const wobble = 0.19 * Math.sin(this.life*0.22 + this.seed);
    this.x += this.vx + wobble;
    this.y += this.vy;
    this.vy += gravity;
    this.alpha -= fade;
    this.life++;
    this.history.push({x:this.x, y:this.y});
    if (this.history.length > this.maxTrail) this.history.shift();
  };
  Particle.prototype.draw = function(ctx) {
    // Draw trailing tail
    for (let j=1; j<this.history.length; j++) {
      ctx.save();
      ctx.globalAlpha = (this.alpha * j / this.history.length) * 0.34;
      ctx.beginPath();
      ctx.moveTo(this.history[j-1].x, this.history[j-1].y);
      ctx.lineTo(this.history[j].x, this.history[j].y);
      ctx.strokeStyle = this.color;
      ctx.lineWidth = Math.max(1, this.size * 0.6 * j / this.history.length);
      ctx.shadowColor = this.color;
      ctx.shadowBlur = 10;
      ctx.stroke();
      ctx.restore();
    }
    // Draw main dot
    ctx.save();
    ctx.globalAlpha = this.alpha;
    ctx.beginPath();
    ctx.arc(this.x, this.y, this.size, 0, 2*Math.PI);
    ctx.fillStyle = this.color;
    ctx.shadowColor = this.color;
    ctx.shadowBlur = 20;
    ctx.fill();
    ctx.restore();
  };

  // --- Firework (single burst) ---
  function Firework(centerX, centerY) {
    // Center burst for performance/premium
    this.x = centerX;
    this.y = centerY;
    this.color = randomColor();
    this.size = 0.7 + Math.random() * 0.6; // Smaller = less overlap, more premium
    this.vx = (Math.random() - 0.5) * 1.7;
    this.vy = -6.2 - Math.random() * 2.1;
    this.state = "launch";
    this.timer = 0;
    this.maxTimer = 11 + Math.random() * 7;
    // 1 in 8 = special burst
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
      this.vy += 0.13;
      this.timer++;
      if (this.timer >= this.maxTimer || this.vy > 0) {
        // Burst into sparks
        this.state = "burst";
        let n = 26 + Math.floor(Math.random() * 12); // Fewer for performance
        for (let i = 0; i < n; i++) {
          let angle, speed, px, py;
          let baseSize = this.size * (0.69 + Math.random()*0.29);
          let type = this.burstType;
          let shape = burstShape(type, n, i);
          if (type === "star") {
            angle = shape.angle;
            speed = 2.7 + Math.random() * 1.3;
          } else if (type === "heart") {
            // Heart-shaped, scaled for burst
            px = this.x + shape.x * 5.2;
            py = this.y + shape.y * 5.2;
            angle = Math.atan2(py-this.y, px-this.x);
            speed = 2.8 + Math.random() * 1.0;
          } else if (type === "ring") {
            angle = shape.angle;
            speed = 4.1 + Math.random() * 0.7;
          } else {
            angle = (i / n) * 2 * Math.PI;
            speed = Math.random() * 3.3 + 1.8;
          }
          let vx = Math.cos(angle) * speed * (type==="heart"?0.6:1);
          let vy = Math.sin(angle) * speed * (type==="heart"?0.7:1);
          this.particles.push(new Particle({
            x: this.x, y: this.y,
            vx: vx, vy: vy,
            alpha: 0.95 + Math.random()*0.08,
            color: randomColor(),
            size: baseSize,
            life: 0,
            seed: Math.random()*1000
          }));
        }
      }
    } else {
      // Physics: gentle gravity, fade
      this.particles.forEach(p => p.update(0.038 + 0.011*(1-p.alpha), 0.012 + Math.random() * 0.011));
      this.particles = this.particles.filter(p => p.alpha > 0.04);
    }
  };
  Firework.prototype.draw = function(ctx) {
    if (this.state === "launch") {
      ctx.save();
      ctx.globalAlpha = 0.52 + 0.09 * Math.random();
      ctx.beginPath();
      ctx.arc(this.x, this.y, this.size * 1.7, 0, 2 * Math.PI);
      ctx.fillStyle = "#fff";
      ctx.shadowColor = this.color;
      ctx.shadowBlur = 13;
      ctx.fill();
      ctx.restore();
    } else {
      this.particles.forEach(p => p.draw(ctx));
    }
  };

  // --- Main public function ---
  window.showFireworks = function(duration = 2000) {
    if (running) return; // Prevent overlap
    running = true;
    resizeCanvas();
    canvas.style.display = "block";
    canvas.style.opacity = "1";

    let fireworks = [];
    let start = null;
    let active = true;

    // Centered for perf + style
    const centerX = canvas.width / 2;
    const centerY = canvas.height * 0.30; // 30% from the top

    // Start a new firework every 260ms, 1 or 2 at a time
    let interval = setInterval(() => {
      if (!active) return;
      const count = 1 + Math.floor(Math.random() * 2);
      for (let i = 0; i < count; i++) fireworks.push(new Firework(centerX, centerY));
    }, 260);

    // Optional vignette overlay
    // const overlay = showOverlay();

    // Animation frame handler
    function animate(ts) {
      if (!start) start = ts;
      ctx.clearRect(0, 0, canvas.width, canvas.height);

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
        // Optional overlay fade-out
        // hideOverlay(overlay);

        // Fade out canvas gently
        canvas.style.transition = "opacity 0.5s";
        canvas.style.opacity = "0";
        setTimeout(() => {
          canvas.style.display = "none";
          canvas.style.opacity = "";
          canvas.style.transition = "";
          running = false;
        }, 520);
      }
    }
    requestAnimationFrame(animate);
  };
})();


// ========== PWA: register the service worker ==========
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(err => console.warn('SW registration failed:', err));
  });
}

