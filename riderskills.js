// =====================================================
// Memory Lanes — riderskills.js
// GPS-based rider skill analysis: cornering, braking,
// entry/exit technique, acceleration smoothness.
//
// Design principle: scores reward SMOOTHNESS, TECHNIQUE and
// CONSISTENCY — never outright speed or lean angle. Lean and
// lateral g are shown as information, not graded.
//
// All estimates derive from GPS positions, so treat them as
// directional feedback, not telemetry-grade truth.
// =====================================================

const G = 9.81;

// ---------- small math helpers ----------
function movingAvg(arr, win) {
  const half = Math.floor(win / 2);
  const out = new Array(arr.length);
  for (let i = 0; i < arr.length; i++) {
    let s = 0, n = 0;
    for (let j = Math.max(0, i - half); j <= Math.min(arr.length - 1, i + half); j++) {
      if (Number.isFinite(arr[j])) { s += arr[j]; n++; }
    }
    out[i] = n ? s / n : 0;
  }
  return out;
}
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
function stdDev(a) {
  if (a.length < 2) return 0;
  const m = a.reduce((s, v) => s + v, 0) / a.length;
  return Math.sqrt(a.reduce((s, v) => s + (v - m) ** 2, 0) / (a.length - 1));
}

// Local flat projection (metres) around a reference point
function projector(refLat, refLng) {
  const kx = 111320 * Math.cos(refLat * Math.PI / 180);
  const ky = 110540;
  return p => ({ x: (p.lng - refLng) * kx, y: (p.lat - refLat) * ky });
}

// Circumradius of three 2D points (metres); Infinity when collinear
function circumradius(a, b, c) {
  const ab = Math.hypot(b.x - a.x, b.y - a.y);
  const bc = Math.hypot(c.x - b.x, c.y - b.y);
  const ca = Math.hypot(a.x - c.x, a.y - c.y);
  const area2 = Math.abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y));
  if (area2 < 1e-6) return Infinity;
  return (ab * bc * ca) / (2 * area2);
}

// =====================================================
// analyzeRide(pts) — pts: [{lat, lng, ele, time:Date}]
// high-resolution (ideally ~1s interval) trackpoints
// =====================================================
export function analyzeRide(pts) {
  if (!Array.isArray(pts) || pts.length < 20) return { ok: false, reason: 'Not enough GPS points for skill analysis.' };
  const t = pts.map(p => p.time.getTime() / 1000);
  const proj = projector(pts[Math.floor(pts.length / 2)].lat, pts[Math.floor(pts.length / 2)].lng);
  const xy = pts.map(proj);

  // Speeds (m/s), smoothed
  const vRaw = new Array(pts.length).fill(0);
  for (let i = 1; i < pts.length; i++) {
    const d = Math.hypot(xy[i].x - xy[i - 1].x, xy[i].y - xy[i - 1].y);
    const dt = t[i] - t[i - 1];
    vRaw[i] = dt > 0 && dt < 60 ? d / dt : vRaw[i - 1];
  }
  vRaw[0] = vRaw[1];
  const v = movingAvg(vRaw, 5);
  const medianDt = (() => {
    const dts = [];
    for (let i = 1; i < t.length; i++) dts.push(t[i] - t[i - 1]);
    dts.sort((a, b) => a - b);
    return dts[Math.floor(dts.length / 2)] || 1;
  })();

  // Longitudinal acceleration (m/s²), smoothed; jerk (m/s³)
  const aRaw = new Array(pts.length).fill(0);
  for (let i = 1; i < pts.length - 1; i++) {
    const dt = t[i + 1] - t[i - 1];
    aRaw[i] = dt > 0 ? (v[i + 1] - v[i - 1]) / dt : 0;
  }
  const a = movingAvg(aRaw, 3);
  const jerk = new Array(pts.length).fill(0);
  for (let i = 1; i < pts.length; i++) {
    const dt = t[i] - t[i - 1];
    jerk[i] = dt > 0 ? (a[i] - a[i - 1]) / dt : 0;
  }

  // Headings & curvature (radius via circumradius over a ±2 sample window)
  const heading = new Array(pts.length).fill(0);
  for (let i = 1; i < pts.length; i++) {
    heading[i] = Math.atan2(xy[i].y - xy[i - 1].y, xy[i].x - xy[i - 1].x);
  }
  heading[0] = heading[1];
  const radius = new Array(pts.length).fill(Infinity);
  const latAcc = new Array(pts.length).fill(0);
  const K = 2;
  for (let i = K; i < pts.length - K; i++) {
    if (v[i] < 2) continue; // ignore walking-pace noise
    const r = circumradius(xy[i - K], xy[i], xy[i + K]);
    radius[i] = clamp(r, 5, 100000);
    latAcc[i] = (v[i] * v[i]) / radius[i];
  }
  const latAccS = movingAvg(latAcc, 3);

  // ---------- Corner detection ----------
  // A corner = contiguous run of meaningful lateral load on a real radius.
  const inCorner = pts.map((_, i) => latAccS[i] >= 1.3 && radius[i] <= 700 && v[i] >= 4);
  const corners = [];
  let start = -1, gap = 0;
  const GAP_ALLOW = Math.max(2, Math.round(3 / medianDt));
  for (let i = 0; i < pts.length; i++) {
    if (inCorner[i]) {
      if (start === -1) start = i;
      gap = 0;
    } else if (start !== -1) {
      gap++;
      if (gap > GAP_ALLOW) {
        corners.push([start, i - gap]);
        start = -1; gap = 0;
      }
    }
  }
  if (start !== -1) corners.push([start, pts.length - 1]);

  function headingSweep(s, e) {
    let sweep = 0;
    for (let i = s + 1; i <= e; i++) {
      let d = heading[i] - heading[i - 1];
      while (d > Math.PI) d -= 2 * Math.PI;
      while (d < -Math.PI) d += 2 * Math.PI;
      sweep += Math.abs(d);
    }
    return sweep * 180 / Math.PI;
  }

  const cornerEvents = [];
  for (const [s, e] of corners) {
    if (e - s < Math.max(2, Math.round(2 / medianDt))) continue;
    const sweep = headingSweep(s, e);
    if (sweep < 25) continue; // ignore gentle bends

    // Apex = point of minimum speed inside the corner (ties → max lateral load)
    let apex = s;
    for (let i = s; i <= e; i++) {
      if (v[i] < v[apex] - 0.05 || (Math.abs(v[i] - v[apex]) <= 0.05 && latAccS[i] > latAccS[apex])) apex = i;
    }
    const preN = Math.max(2, Math.round(4 / medianDt));
    const entryIdx = Math.max(0, s - preN);
    const entrySpeed = v[s];
    const apexSpeed = v[apex];
    const exitSpeed = v[e];
    let minR = Infinity;
    for (let i = s; i <= e; i++) if (radius[i] < minR) minR = radius[i];
    const maxLat = Math.max(...latAccS.slice(s, e + 1));
    const leanDeg = Math.atan(maxLat / G) * 180 / Math.PI;

    // How deep into the corner does braking continue? (0 = all done before turn-in)
    let lastBrake = -1;
    for (let i = s; i <= apex; i++) if (a[i] < -0.8) lastBrake = i;
    const brakeDepth = lastBrake === -1 ? 0 : (lastBrake - s) / Math.max(1, apex - s);

    // Drive off the apex (mean accel apex → exit)
    let driveSum = 0, driveN = 0;
    for (let i = apex; i <= e; i++) { driveSum += a[i]; driveN++; }
    const drive = driveN ? driveSum / driveN : 0;

    const apexPos = (apex - s) / Math.max(1, e - s);

    // Rule-based coaching verdicts — technique-focused, never "go faster"
    const notes = [];
    if (brakeDepth > 0.6) notes.push('braking carried deep toward the apex — try finishing braking earlier so the bike is settled for turn-in');
    else if (brakeDepth > 0.25) notes.push('light trail-braking into the corner');
    else notes.push('braking done before turn-in — settled entry');
    if (apexPos >= 0.55) notes.push('late apex — good road-riding line');
    else if (apexPos <= 0.35) notes.push('early apex — this can run you wide on exit');
    if (drive >= 0.5 && exitSpeed > apexSpeed * 1.08) notes.push('strong, progressive drive off the corner');
    else if (drive < 0.1) notes.push('little drive on exit — pick the bike up and open the throttle progressively once you can see the exit');

    cornerEvents.push({
      startIdx: s, apexIdx: apex, endIdx: e, entryIdx,
      tStart: pts[s].time, tApex: pts[apex].time,
      sweepDeg: sweep, radiusM: minR,
      entryKmh: entrySpeed * 3.6, apexKmh: apexSpeed * 3.6, exitKmh: exitSpeed * 3.6,
      maxLatG: maxLat / G, leanDeg,
      brakeDepth, drive, apexPos,
      note: notes.join('; ')
    });
  }

  // ---------- Braking & acceleration zones ----------
  function detectZones(cond) {
    const zones = [];
    let zs = -1;
    for (let i = 0; i < pts.length; i++) {
      if (cond(i)) { if (zs === -1) zs = i; }
      else if (zs !== -1) {
        if (i - zs >= Math.max(2, Math.round(2 / medianDt))) zones.push([zs, i - 1]);
        zs = -1;
      }
    }
    if (zs !== -1 && pts.length - zs >= 2) zones.push([zs, pts.length - 1]);
    return zones;
  }
  const brakeZones = detectZones(i => a[i] <= -1.4 && v[i] > 3).map(([s, e]) => {
    const seg = a.slice(s, e + 1);
    const jseg = jerk.slice(s + 1, e + 1);
    return {
      startIdx: s, endIdx: e, tStart: pts[s].time,
      fromKmh: v[s] * 3.6, toKmh: v[e] * 3.6,
      peakDecel: Math.min(...seg), meanDecel: seg.reduce((x, y) => x + y, 0) / seg.length,
      smoothness: clamp(100 - stdDev(jseg) * 55, 0, 100)
    };
  });
  const accelZones = detectZones(i => a[i] >= 1.2 && v[i] > 3).map(([s, e]) => {
    const jseg = jerk.slice(s + 1, e + 1);
    return { startIdx: s, endIdx: e, smoothness: clamp(100 - stdDev(jseg) * 55, 0, 100) };
  });

  // ---------- Scores (0–100, technique-based) ----------
  const scores = {};
  if (cornerEvents.length >= 3) {
    scores.cornerEntry = Math.round(100 * cornerEvents.filter(c => c.brakeDepth <= 0.4).length / cornerEvents.length);
    const meanDrive = cornerEvents.reduce((s2, c) => s2 + Math.max(0, c.drive), 0) / cornerEvents.length;
    scores.exitDrive = Math.round(clamp(meanDrive / 1.2, 0, 1) * 100);
    // Consistency: apex-speed spread within similar-radius corners
    const buckets = { tight: [], medium: [], open: [] };
    cornerEvents.forEach(c => {
      (c.radiusM < 60 ? buckets.tight : c.radiusM < 180 ? buckets.medium : buckets.open).push(c.apexKmh);
    });
    const cvs = Object.values(buckets)
      .filter(b => b.length >= 3)
      .map(b => stdDev(b) / (b.reduce((x, y) => x + y, 0) / b.length));
    if (cvs.length) {
      scores.consistency = Math.round(clamp(100 - (cvs.reduce((x, y) => x + y, 0) / cvs.length) * 320, 0, 100));
    }
  }
  if (brakeZones.length >= 2) {
    scores.brakingSmoothness = Math.round(brakeZones.reduce((s2, z) => s2 + z.smoothness, 0) / brakeZones.length);
  }
  if (accelZones.length >= 2) {
    scores.throttleSmoothness = Math.round(accelZones.reduce((s2, z) => s2 + z.smoothness, 0) / accelZones.length);
  }

  return {
    ok: true,
    sampleIntervalS: medianDt,
    corners: cornerEvents,
    brakeZones,
    accelZonesCount: accelZones.length,
    scores
  };
}

// =====================================================
// renderRiderSkills(analysis, opts) — browser-only rendering.
// opts: { radarCanvasId, cornersListId, brakingSummaryId, jumpToTime }
// =====================================================
export function renderRiderSkills(analysis, opts) {
  const cornersList = document.getElementById(opts.cornersListId);
  const brakingEl = document.getElementById(opts.brakingSummaryId);
  const radarCanvas = document.getElementById(opts.radarCanvasId);
  if (!cornersList || !brakingEl || !radarCanvas) return;

  if (!analysis.ok) {
    cornersList.innerHTML = `<em>${analysis.reason}</em>`;
    brakingEl.textContent = '';
    radarCanvas.style.display = 'none';
    return;
  }
  radarCanvas.style.display = '';

  if (analysis.sampleIntervalS > 3.5) {
    brakingEl.innerHTML = `<em>⚠️ This GPX records a point every ~${analysis.sampleIntervalS.toFixed(0)}s, which is coarse for skill analysis — a 1s logging interval gives much sharper feedback.</em><br><br>`;
  } else {
    brakingEl.innerHTML = '';
  }

  // --- Radar chart of technique scores ---
  const axisDefs = [
    ['cornerEntry', 'Corner Entry'],
    ['exitDrive', 'Exit Drive'],
    ['brakingSmoothness', 'Braking Smoothness'],
    ['throttleSmoothness', 'Throttle Smoothness'],
    ['consistency', 'Consistency']
  ].filter(([k]) => Number.isFinite(analysis.scores[k]));

  if (window.riderRadarChart && typeof window.riderRadarChart.destroy === 'function') {
    window.riderRadarChart.destroy();
  }
  if (axisDefs.length >= 3) {
    window.riderRadarChart = new Chart(radarCanvas.getContext('2d'), {
      type: 'radar',
      data: {
        labels: axisDefs.map(([, label]) => label),
        datasets: [{
          label: 'Technique (0–100)',
          data: axisDefs.map(([k]) => analysis.scores[k]),
          backgroundColor: 'rgba(100,255,218,0.22)',
          borderColor: '#64ffda',
          pointBackgroundColor: '#00c6ff',
          borderWidth: 2
        }]
      },
      options: {
        responsive: true,
        scales: {
          r: {
            min: 0, max: 100, ticks: { stepSize: 25, backdropColor: 'transparent', color: '#8fa4bd' },
            grid: { color: '#2a3a55' }, angleLines: { color: '#2a3a55' },
            pointLabels: { color: '#c5d1e3', font: { size: 13 } }
          }
        },
        plugins: { legend: { display: false } }
      }
    });
  } else {
    radarCanvas.style.display = 'none';
    brakingEl.innerHTML += '<em>Not enough corners/braking events in this ride for technique scores — the corner list below still shows what was found.</em><br><br>';
  }

  // --- Braking summary ---
  if (analysis.brakeZones.length) {
    const peak = Math.min(...analysis.brakeZones.map(z => z.peakDecel));
    const meanSmooth = analysis.brakeZones.reduce((s, z) => s + z.smoothness, 0) / analysis.brakeZones.length;
    const verdict = meanSmooth >= 70 ? 'progressive and controlled'
      : meanSmooth >= 45 ? 'mostly smooth, occasionally grabby'
      : 'abrupt — practise squeezing the lever progressively';
    brakingEl.innerHTML += `🛑 <strong>${analysis.brakeZones.length} braking zones</strong> · hardest stop ${Math.abs(peak).toFixed(1)} m/s² (${(Math.abs(peak) / G).toFixed(2)} g) · overall: ${verdict}.`;
  }

  // --- Corner cards (top 10 by lateral load) ---
  const top = [...analysis.corners].sort((x, y) => y.maxLatG - x.maxLatG).slice(0, 10);
  if (!top.length) {
    cornersList.innerHTML = '<em>No significant corners detected in this ride.</em>';
    return;
  }
  cornersList.innerHTML = '';
  top.forEach((c, i) => {
    const div = document.createElement('div');
    div.className = 'corner-card';
    div.innerHTML = `
      <div class="corner-head">
        <span class="corner-rank">#${i + 1}</span>
        <span class="corner-geo">${c.sweepDeg.toFixed(0)}° sweep · r≈${c.radiusM.toFixed(0)} m · est. lean ${c.leanDeg.toFixed(0)}° (${c.maxLatG.toFixed(2)} g)</span>
        <button class="btn-muted corner-jump">Jump</button>
      </div>
      <div class="corner-speeds">
        <span>IN <strong>${c.entryKmh.toFixed(0)}</strong></span> →
        <span>APEX <strong>${c.apexKmh.toFixed(0)}</strong></span> →
        <span>OUT <strong>${c.exitKmh.toFixed(0)}</strong> km/h</span>
      </div>
      <div class="corner-note">${c.note}</div>
    `;
    div.querySelector('.corner-jump').addEventListener('click', () => opts.jumpToTime(c.tApex));
    cornersList.appendChild(div);
  });
}
