// ===============================
// Memory Lanes - stats.js
// Lifetime stats: totals, monthly chart, personal bests, all-routes map
// ===============================
import supabase from './supabaseClient.js';
import { analyzeRide, summarizeForStorage } from './riderskills.js?v=53';

const ROUTE_COLORS = ['#64ffda', '#00c6ff', '#8338ec', '#ff6384', '#ffd700', '#21c821', '#ff9500'];
const MAX_ROUTES_ON_MAP = 100;   // safety cap for very large journals
const MAX_POINTS_PER_ROUTE = 200; // downsample each route for performance

function fmtDuration(totalMin) {
  const h = Math.floor(totalMin / 60);
  const m = Math.round(totalMin % 60);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

(async () => {
  // Auth gate - stats are personal
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    window.location.href = 'index.html';
    return;
  }

  // Try to include skill summaries; fall back gracefully if the column is not migrated yet
  let skillsAvailable = true;
  let { data: rides, error: fetchErr } = await supabase
    .from('ride_logs')
    .select('id, title, distance_km, duration_min, elevation_m, ride_date, gpx_path, skills')
    .eq('user_id', user.id)
    .order('ride_date', { ascending: false });
  if (fetchErr && /skills/i.test(fetchErr.message || '')) {
    skillsAvailable = false;
    ({ data: rides, error: fetchErr } = await supabase
      .from('ride_logs')
      .select('id, title, distance_km, duration_min, elevation_m, ride_date, gpx_path')
      .eq('user_id', user.id)
      .order('ride_date', { ascending: false }));
  }

  if (fetchErr) {
    document.getElementById('stats-empty').style.display = 'block';
    document.getElementById('stats-empty').textContent = 'Could not load your rides. Please try again.';
    return;
  }

  if (!rides || !rides.length) {
    document.getElementById('stats-empty').style.display = 'block';
    return;
  }

  // ---------- Totals ----------
  const totalKm = rides.reduce((s, r) => s + (r.distance_km || 0), 0);
  const totalElev = rides.reduce((s, r) => s + (r.elevation_m || 0), 0);
  const totalMin = rides.reduce((s, r) => s + (r.duration_min || 0), 0);
  document.getElementById('total-rides').textContent = rides.length;
  document.getElementById('total-distance').textContent = `${totalKm.toFixed(0)} km`;
  document.getElementById('total-elevation').textContent = `${totalElev.toFixed(0)} m`;
  document.getElementById('total-time').textContent = fmtDuration(totalMin);
  document.getElementById('totals-grid').style.display = 'grid';

  // ---------- Rides per month (last 12 months) ----------
  const now = new Date();
  const months = [];
  for (let i = 11; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    months.push({ key: `${d.getFullYear()}-${d.getMonth()}`, label: d.toLocaleString('default', { month: 'short', year: '2-digit' }), km: 0, count: 0 });
  }
  const monthIndex = new Map(months.map((m, i) => [m.key, i]));
  rides.forEach(r => {
    if (!r.ride_date) return;
    const d = new Date(r.ride_date);
    const idx = monthIndex.get(`${d.getFullYear()}-${d.getMonth()}`);
    if (idx !== undefined) {
      months[idx].km += r.distance_km || 0;
      months[idx].count += 1;
    }
  });

  document.getElementById('month-block').style.display = 'block';
  const mctx = document.getElementById('monthChart').getContext('2d');
  const grad = mctx.createLinearGradient(0, 0, 0, 300);
  grad.addColorStop(0, 'rgba(100,255,218,0.85)');
  grad.addColorStop(1, 'rgba(0,198,255,0.45)');
  new Chart(mctx, {
    type: 'bar',
    data: {
      labels: months.map(m => m.label),
      datasets: [{ label: 'Distance (km)', data: months.map(m => +m.km.toFixed(1)), backgroundColor: grad, borderRadius: 8 }]
    },
    options: {
      responsive: true,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: ctx => {
              const m = months[ctx.dataIndex];
              return `${m.km.toFixed(1)} km · ${m.count} ride${m.count === 1 ? '' : 's'}`;
            }
          }
        }
      },
      scales: {
        x: { grid: { color: '#223' } },
        y: { title: { display: true, text: 'km' }, grid: { color: '#334' }, beginAtZero: true }
      }
    }
  });

  // ---------- Skill trends ----------
  const trendsBlock = document.getElementById('trends-block');
  const trendsStatus = document.getElementById('trends-status');
  const analyzeBtn = document.getElementById('analyze-past-btn');
  trendsBlock.style.display = 'block';

  const AXES = [
    ['cornerEntry', 'Corner entry', '#64ffda'],
    ['exitDrive', 'Exit drive', '#00c6ff'],
    ['brakingSmoothness', 'Braking feel', '#ff6384'],
    ['throttleSmoothness', 'Throttle feel', '#ffd166'],
    ['consistency', 'Consistency', '#8338ec']
  ];
  let trendsChart = null;

  function renderTrends() {
    const scored = rides
      .filter(r => r.skills && r.skills.scores && r.ride_date)
      .sort((a, b) => new Date(a.ride_date) - new Date(b.ride_date))
      .slice(-30);
    if (!skillsAvailable) {
      trendsStatus.textContent = 'Skill trends need a one-time database setup: run supabase-skills-setup.sql in Supabase, then revisit a ride to record its scores.';
      return;
    }
    if (scored.length < 2) {
      trendsStatus.textContent = scored.length === 0
        ? 'No skill scores recorded yet. Open a ride to analyze it, or use the button below to analyze your past rides in one go.'
        : 'One ride scored so far. Trends appear once a second ride is analyzed.';
      const unscored = rides.filter(r => !r.skills && r.gpx_path).length;
      if (unscored > 0) {
        analyzeBtn.style.display = 'inline-block';
        analyzeBtn.textContent = `Analyze past rides (${Math.min(unscored, 25)} of ${unscored})`;
      }
      return;
    }
    const labels = scored.map(r => new Date(r.ride_date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }));
    if (trendsChart) trendsChart.destroy();
    trendsChart = new Chart(document.getElementById('trendsChart').getContext('2d'), {
      type: 'line',
      data: {
        labels,
        datasets: AXES
          .filter(([k]) => scored.some(r => Number.isFinite(r.skills.scores[k])))
          .map(([k, label, color]) => ({
            label,
            data: scored.map(r => Number.isFinite(r.skills.scores[k]) ? r.skills.scores[k] : null),
            borderColor: color, backgroundColor: color,
            borderWidth: 2, pointRadius: 3, tension: 0.25, spanGaps: true
          }))
      },
      options: {
        responsive: true,
        scales: {
          y: { min: 0, max: 100, grid: { color: '#334' } },
          x: { grid: { color: '#223' } }
        },
        plugins: { legend: { labels: { color: '#c5d1e3' } } }
      }
    });
    const unscored = rides.filter(r => !r.skills && r.gpx_path).length;
    trendsStatus.textContent = `${scored.length} rides scored.` + (unscored ? ` ${unscored} older rides not yet analyzed.` : '');
    if (unscored > 0) {
      analyzeBtn.style.display = 'inline-block';
      analyzeBtn.textContent = `Analyze past rides (${Math.min(unscored, 25)} of ${unscored})`;
    } else {
      analyzeBtn.style.display = 'none';
    }
  }
  renderTrends();

  // Backfill: fetch GPX for unscored rides, run the Ride Coach engine, store summaries
  analyzeBtn?.addEventListener('click', async () => {
    if (!skillsAvailable) return;
    analyzeBtn.disabled = true;
    const targets = rides.filter(r => !r.skills && r.gpx_path).slice(0, 25);
    let done = 0, failed = 0;
    for (const ride of targets) {
      try {
        const { data: urlData } = supabase.storage.from('gpx-files').getPublicUrl(ride.gpx_path);
        const resp = await fetch(urlData.publicUrl);
        if (!resp.ok) throw new Error('gpx ' + resp.status);
        const xml = new DOMParser().parseFromString(await resp.text(), 'application/xml');
        const raw = Array.from(xml.getElementsByTagName('trkpt')).map(tp => ({
          lat: +tp.getAttribute('lat'),
          lng: +tp.getAttribute('lon'),
          ele: +(tp.getElementsByTagName('ele')[0]?.textContent || 0),
          time: new Date(tp.getElementsByTagName('time')[0]?.textContent)
        })).filter(p => Number.isFinite(p.lat) && Number.isFinite(p.lng) && !isNaN(p.time));
        let hi = [];
        let lastT = -Infinity;
        for (const tp of raw) {
          const ts = tp.time.getTime();
          if (ts - lastT >= 950) { hi.push(tp); lastT = ts; }
        }
        if (hi.length > 15000) {
          const stride = Math.ceil(hi.length / 15000);
          hi = hi.filter((_, i) => i % stride === 0);
        }
        const analysis = analyzeRide(hi);
        const summary = analysis.ok ? summarizeForStorage(analysis) : { v: 1, at: new Date().toISOString(), scores: {}, comp: {}, corners: [], note: 'insufficient data' };
        const { error: upErr } = await supabase.from('ride_logs').update({ skills: summary }).eq('id', ride.id).eq('user_id', user.id);
        if (upErr) throw upErr;
        ride.skills = summary;
        done++;
      } catch (e) {
        failed++;
        console.warn('Backfill failed for ride', ride.id, e);
      }
      trendsStatus.textContent = `Analyzing past rides: ${done + failed}/${targets.length} (${failed} failed)`;
    }
    analyzeBtn.disabled = false;
    renderTrends();
  });

  // ---------- Personal bests ----------
  const byTitle = r => r.title || '(untitled ride)';
  const goodDur = rides.filter(r => (r.duration_min || 0) > 0 && (r.distance_km || 0) >= 5);
  const bests = [];
  const longest = [...rides].sort((a, b) => (b.distance_km || 0) - (a.distance_km || 0))[0];
  if (longest) bests.push({ label: 'Longest Ride', value: `${(longest.distance_km || 0).toFixed(1)} km`, ride: longest });
  const climb = [...rides].sort((a, b) => (b.elevation_m || 0) - (a.elevation_m || 0))[0];
  if (climb) bests.push({ label: 'Biggest Climb', value: `${(climb.elevation_m || 0).toFixed(0)} m`, ride: climb });
  const marathon = [...rides].sort((a, b) => (b.duration_min || 0) - (a.duration_min || 0))[0];
  if (marathon) bests.push({ label: 'Longest Time Out', value: fmtDuration(marathon.duration_min || 0), ride: marathon });
  if (goodDur.length) {
    const fastest = [...goodDur].sort((a, b) =>
      (b.distance_km / (b.duration_min / 60)) - (a.distance_km / (a.duration_min / 60)))[0];
    bests.push({ label: 'Best Avg Speed', value: `${(fastest.distance_km / (fastest.duration_min / 60)).toFixed(1)} km/h`, ride: fastest });
  }

  const bestsGrid = document.getElementById('bests-grid');
  bests.forEach(b => {
    const card = document.createElement('div');
    card.className = 'best-card';
    const label = document.createElement('div');
    label.className = 'best-label';
    label.textContent = b.label;
    const value = document.createElement('div');
    value.className = 'best-value';
    value.textContent = b.value;
    const title = document.createElement('div');
    title.className = 'best-title';
    const dateStr = b.ride.ride_date ? ` · ${new Date(b.ride.ride_date).toLocaleDateString()}` : '';
    title.textContent = byTitle(b.ride) + dateStr;
    card.append(label, value, title);
    card.addEventListener('click', () => { window.location.href = `index.html?ride=${b.ride.id}`; });
    bestsGrid.appendChild(card);
  });
  document.getElementById('bests-block').style.display = 'block';

  // ---------- Map of everywhere you've ridden ----------
  document.getElementById('map-block').style.display = 'block';
  const map = L.map('all-routes-map').setView([20, 0], 2);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);
  setTimeout(() => map.invalidateSize(), 150);

  const progress = document.getElementById('routes-progress');
  const toLoad = rides.filter(r => r.gpx_path).slice(0, MAX_ROUTES_ON_MAP);
  let bounds = null;
  let loaded = 0, failed = 0;

  async function loadRoute(ride, colorIdx) {
    try {
      const { data: urlData } = supabase.storage.from('gpx-files').getPublicUrl(ride.gpx_path);
      const resp = await fetch(urlData.publicUrl);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const xml = new DOMParser().parseFromString(await resp.text(), 'application/xml');
      const trkpts = xml.getElementsByTagName('trkpt');
      if (!trkpts.length) throw new Error('no points');
      const stride = Math.max(1, Math.floor(trkpts.length / MAX_POINTS_PER_ROUTE));
      const latlngs = [];
      for (let i = 0; i < trkpts.length; i += stride) {
        const lat = +trkpts[i].getAttribute('lat');
        const lng = +trkpts[i].getAttribute('lon');
        if (Number.isFinite(lat) && Number.isFinite(lng)) latlngs.push([lat, lng]);
      }
      const last = trkpts[trkpts.length - 1];
      latlngs.push([+last.getAttribute('lat'), +last.getAttribute('lon')]);
      if (latlngs.length < 2) throw new Error('too few points');

      const line = L.polyline(latlngs, {
        color: ROUTE_COLORS[colorIdx % ROUTE_COLORS.length],
        weight: 3, opacity: 0.75
      }).addTo(map);
      line.bindTooltip(ride.title || 'Ride', { sticky: true });
      line.on('click', () => { window.location.href = `index.html?ride=${ride.id}`; });
      bounds = bounds ? bounds.extend(line.getBounds()) : L.latLngBounds(line.getBounds().getSouthWest(), line.getBounds().getNorthEast());
    } catch (_) {
      failed++;
    } finally {
      loaded++;
      progress.textContent = `Loading routes… ${loaded}/${toLoad.length}`;
    }
  }

  // Load in small batches so the browser and storage stay happy
  const BATCH = 6;
  for (let i = 0; i < toLoad.length; i += BATCH) {
    await Promise.all(toLoad.slice(i, i + BATCH).map((r, j) => loadRoute(r, i + j)));
    if (bounds) map.fitBounds(bounds, { padding: [30, 30] });
  }
  progress.textContent = failed
    ? `Showing ${toLoad.length - failed} of ${toLoad.length} routes (${failed} could not be loaded). Click a route to open that ride.`
    : `Showing all ${toLoad.length} routes. Click a route to open that ride.`;
  if (rides.length > MAX_ROUTES_ON_MAP) {
    progress.textContent += ` Map shows your ${MAX_ROUTES_ON_MAP} most recent rides.`;
  }
})();

// Nav buttons
document.getElementById('back-dashboard-btn')?.addEventListener('click', () => window.location.href = 'dashboard.html');
document.getElementById('new-ride-btn')?.addEventListener('click', () => window.location.href = 'index.html?home=1');


// ========== PWA: register the service worker ==========
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(err => console.warn('SW registration failed:', err));
  });
}
