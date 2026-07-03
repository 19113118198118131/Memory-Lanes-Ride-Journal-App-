// =====================================================
// Memory Lanes - riderskills.js
// GPS-based rider skill analysis: cornering, braking,
// entry/exit technique, acceleration smoothness.
//
// Design principle: scores reward SMOOTHNESS, TECHNIQUE and
// CONSISTENCY, never outright speed or lean angle. Lean and
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
// analyzeRide(pts) - pts: [{lat, lng, ele, time:Date}]
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
  const dist = new Array(pts.length).fill(0);
  for (let i = 1; i < pts.length; i++) {
    dist[i] = dist[i - 1] + Math.hypot(xy[i].x - xy[i - 1].x, xy[i].y - xy[i - 1].y);
  }
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

    // Rule-based verdicts as scannable chips + one focus tip. Technique-focused, never "go faster".
    const tags = [];
    let focus = '';
    if (brakeDepth > 0.6) {
      tags.push({ label: 'Braked deep', tone: 'tip' });
      focus = 'Finish braking earlier so the bike is settled before turn-in.';
    } else if (brakeDepth > 0.25) {
      tags.push({ label: 'Trail braking', tone: 'neutral' });
    } else {
      tags.push({ label: 'Settled entry', tone: 'good' });
    }
    if (apexPos >= 0.55) tags.push({ label: 'Late apex', tone: 'good' });
    else if (apexPos <= 0.35) {
      tags.push({ label: 'Early apex', tone: 'tip' });
      if (!focus) focus = 'An early apex can run you wide on exit. Turn in a touch later.';
    } else tags.push({ label: 'Mid apex', tone: 'neutral' });
    if (drive >= 0.5 && exitSpeed > apexSpeed * 1.08) tags.push({ label: 'Strong drive', tone: 'good' });
    else if (drive < 0.1) {
      tags.push({ label: 'Flat exit', tone: 'tip' });
      if (!focus) focus = 'Pick the bike up and roll the throttle on progressively once you can see the exit.';
    }

    let headingAtApex = heading[apex] * 180 / Math.PI;
    if (headingAtApex < 0) headingAtApex += 360;
    cornerEvents.push({
      startIdx: s, apexIdx: apex, endIdx: e, entryIdx,
      apexLat: pts[apex].lat, apexLng: pts[apex].lng, apexHeadingDeg: headingAtApex,
      tStart: pts[s].time, tApex: pts[apex].time,
      sweepDeg: sweep, radiusM: minR,
      entryKmh: entrySpeed * 3.6, apexKmh: apexSpeed * 3.6, exitKmh: exitSpeed * 3.6,
      maxLatG: maxLat / G, leanDeg,
      brakeDepth, drive, apexPos,
      tags, focus
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
      startKm: dist[s] / 1000, endKm: dist[e] / 1000,
      fromKmh: v[s] * 3.6, toKmh: v[e] * 3.6,
      peakDecel: Math.min(...seg), meanDecel: seg.reduce((x, y) => x + y, 0) / seg.length,
      smoothness: clamp(100 - stdDev(jseg) * 55, 0, 100)
    };
  });
  const accelZones = detectZones(i => a[i] >= 1.2 && v[i] > 3).map(([s, e]) => {
    const jseg = jerk.slice(s + 1, e + 1);
    return { startIdx: s, endIdx: e, startKm: dist[s] / 1000, endKm: dist[e] / 1000,
      smoothness: clamp(100 - stdDev(jseg) * 55, 0, 100) };
  });

  // ---------- Ride composition (each sample counted once, by priority) ----------
  const inBrake = new Array(pts.length).fill(false);
  brakeZones.forEach(z => { for (let i = z.startIdx; i <= z.endIdx; i++) inBrake[i] = true; });
  const inDrive = new Array(pts.length).fill(false);
  accelZones.forEach(z => { for (let i = z.startIdx; i <= z.endIdx; i++) inDrive[i] = true; });
  const composition = { stopped: 0, cornering: 0, braking: 0, driving: 0, cruising: 0 };
  for (let i = 1; i < pts.length; i++) {
    const dt = Math.min(10, Math.max(0, t[i] - t[i - 1]));
    if (v[i] < 1) composition.stopped += dt;
    else if (inCorner[i]) composition.cornering += dt;
    else if (inBrake[i]) composition.braking += dt;
    else if (inDrive[i]) composition.driving += dt;
    else composition.cruising += dt;
  }

  // ---------- g-g cloud (signed lateral, for the friction-circle diagram) ----------
  const ggPoints = [];
  {
    const stride = Math.max(1, Math.ceil(pts.length / 1500));
    for (let i = 1; i < pts.length - 1; i += stride) {
      if (v[i] < 3) continue;
      let dHead = heading[i + 1] - heading[i - 1];
      while (dHead > Math.PI) dHead -= 2 * Math.PI;
      while (dHead < -Math.PI) dHead += 2 * Math.PI;
      const sign = dHead >= 0 ? 1 : -1;
      ggPoints.push({ x: +(sign * latAccS[i] / G).toFixed(3), y: +(a[i] / G).toFixed(3) });
    }
  }

  // ---------- Smoothed acceleration series over distance (for the profile chart) ----------
  const accelSeries = [];
  {
    const stride = Math.max(1, Math.ceil(pts.length / 1500));
    for (let i = 0; i < pts.length; i += stride) {
      accelSeries.push({ x: +(dist[i] / 1000).toFixed(3), y: +a[i].toFixed(3) });
    }
  }

  // ---------- Scores (0 to 100, technique-based) ----------
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
    accelZones,
    accelZonesCount: accelZones.length,
    composition,
    ggPoints,
    accelSeries,
    totalKm: dist[dist.length - 1] / 1000,
    scores
  };
}

// =====================================================
// RENDERING: full-width layout, technique radar hero,
// skill meters, corner ticket grid.
// Pure HTML builders (testable) + a thin DOM wrapper.
// =====================================================

const TONE_CLASS = { good: 'chip-good', tip: 'chip-tip', neutral: 'chip-neutral' };

function esc(v) {
  return String(v ?? '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// SVG arc glyph: curvature reflects the corner's real radius, arc length its sweep
export function cornerGlyphSVG(sweepDeg, radiusM) {
  const size = 64, cx = size / 2, cy = size / 2 + 4;
  const drawR = clamp(12 + (clamp(radiusM, 20, 300) / 300) * 14, 12, 26);
  const sweep = clamp(sweepDeg, 30, 300) * Math.PI / 180;
  const a0 = -Math.PI / 2 - sweep / 2;
  const a1 = -Math.PI / 2 + sweep / 2;
  const x0 = cx + drawR * Math.cos(a0), y0 = cy + drawR * Math.sin(a0);
  const x1 = cx + drawR * Math.cos(a1), y1 = cy + drawR * Math.sin(a1);
  const largeArc = sweep > Math.PI ? 1 : 0;
  return `<svg class="corner-glyph" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" aria-hidden="true">
    <path d="M ${x0.toFixed(1)} ${y0.toFixed(1)} A ${drawR} ${drawR} 0 ${largeArc} 1 ${x1.toFixed(1)} ${y1.toFixed(1)}"
      fill="none" stroke="url(#corner-grad)" stroke-width="4.5" stroke-linecap="round"/>
    <circle cx="${cx}" cy="${(cy - drawR).toFixed(1)}" r="3.6" fill="#fff"/>
  </svg>`;
}

const GRADE_BANDS = [
  [85, 'Silky smooth'],
  [70, 'Composed'],
  [55, 'Finding the rhythm'],
  [0, 'Rough edges, plenty to gain']
];

const AXIS_LABELS = {
  cornerEntry: 'Corner entry',
  exitDrive: 'Exit drive',
  brakingSmoothness: 'Braking feel',
  throttleSmoothness: 'Throttle feel',
  consistency: 'Consistency'
};

const METER_CAPS = {
  cornerEntry: {
    hi: 'Braking is done before turn-in. The bike arrives settled.',
    mid: 'Entries are mostly tidy. A few corners still get braking carried in.',
    lo: 'Braking often runs deep into corners. The biggest single thing to work on.'
  },
  exitDrive: {
    hi: 'Strong, progressive throttle off the apex.',
    mid: 'Decent drive out. There is more corner-exit speed on the table.',
    lo: 'Exits are flat. Practise opening the throttle earlier and smoother.'
  },
  brakingSmoothness: {
    hi: 'Progressive on the lever. Smooth, controlled stops.',
    mid: 'Mostly smooth braking with the occasional grab.',
    lo: 'Braking is abrupt. Squeeze, don\u2019t snatch.'
  },
  throttleSmoothness: {
    hi: 'Clean, progressive acceleration.',
    mid: 'Throttle work is decent, sometimes jumpy.',
    lo: 'Acceleration comes in bursts. Smooth it out.'
  },
  consistency: {
    hi: 'Similar corners get near-identical treatment. Repeatable is skilled.',
    mid: 'Corner speeds vary a fair bit between similar corners.',
    lo: 'Similar corners are ridden very differently. Aim for repeatability.'
  }
};

// Compact per-ride summary for storage in ride_logs.skills (jsonb).
// Kept small: scores, composition, and up to 40 corner fingerprints
// (location + heading + geometry) for trends and repeat-corner recognition.
export function summarizeForStorage(analysis) {
  if (!analysis.ok) return null;
  const corners = [...analysis.corners]
    .sort((a, b) => b.maxLatG - a.maxLatG)
    .slice(0, 40)
    .map(c => ({
      la: +c.apexLat.toFixed(5), ln: +c.apexLng.toFixed(5),
      hd: Math.round(c.apexHeadingDeg),
      ak: Math.round(c.apexKmh), r: Math.round(c.radiusM),
      sw: Math.round(c.sweepDeg), ld: Math.round(c.leanDeg)
    }));
  const comp = {};
  Object.entries(analysis.composition).forEach(([k, sec]) => { comp[k] = Math.round(sec); });
  return { v: 1, at: new Date().toISOString(), scores: analysis.scores, comp, corners };
}

// Plain-English debrief: turns the score spread into a coach's summary.
const STRENGTH_CLAUSE = {
  cornerEntry: 'entries were settled, with braking done before turn-in',
  exitDrive: 'drive off the corners was strong',
  brakingSmoothness: 'braking was progressive and controlled',
  throttleSmoothness: 'throttle work was clean',
  consistency: 'similar corners got near-identical treatment'
};
const WEAKNESS_CLAUSE = {
  cornerEntry: 'braking often ran into the corners',
  exitDrive: 'exits were flatter than they could be',
  brakingSmoothness: 'braking was on the abrupt side',
  throttleSmoothness: 'throttle inputs were a little jumpy',
  consistency: 'similar corners were ridden quite differently'
};
const FOCUS_PHRASE = {
  cornerEntry: 'finishing your braking before turn-in, so the bike arrives settled',
  exitDrive: 'picking the bike up earlier, then rolling the throttle on progressively',
  brakingSmoothness: 'squeezing the brake progressively rather than snatching it',
  throttleSmoothness: 'smoother, earlier throttle once the corner opens up',
  consistency: 'treating similar corners the same way, ride after ride'
};

export function buildDebrief(scores) {
  const keys = Object.keys(scores).filter(k => Number.isFinite(scores[k]));
  if (keys.length < 2) return null;
  const hi = keys.reduce((a, b) => (scores[a] >= scores[b] ? a : b));
  const lo = keys.reduce((a, b) => (scores[a] <= scores[b] ? a : b));
  if (scores[hi] - scores[lo] < 12) {
    return {
      verdict: 'A balanced ride across the board.',
      next: 'Next ride: keep building on this consistency.'
    };
  }
  const strong = STRENGTH_CLAUSE[hi];
  const verdict = strong.charAt(0).toUpperCase() + strong.slice(1) + ', but ' + WEAKNESS_CLAUSE[lo] + '.';
  return { verdict, next: 'Next ride: focus on ' + FOCUS_PHRASE[lo] + '.' };
}

const COMP_META = {
  cornering: ['Cornering', '#64ffda'],
  braking: ['Braking', '#ff6384'],
  driving: ['Driving', '#21c821'],
  cruising: ['Cruising', '#3a86ff'],
  stopped: ['Stopped', '#55607a']
};

export function compositionBarHTML(comp) {
  if (!comp) return '';
  const total = Object.values(comp).reduce((a, b) => a + b, 0);
  if (total < 60) return '';
  const order = ['cornering', 'braking', 'driving', 'cruising', 'stopped'];
  const segs = order
    .map(k => ({ k, pct: 100 * (comp[k] || 0) / total }))
    .filter(sg => sg.pct >= 0.5);
  const bar = segs.map(sg =>
    `<span class="comp-seg" style="width:${sg.pct.toFixed(1)}%;background:${COMP_META[sg.k][1]}" title="${COMP_META[sg.k][0]} ${sg.pct.toFixed(0)}%"></span>`
  ).join('');
  const legend = segs.map(sg =>
    `<span class="comp-key"><span class="comp-dot" style="background:${COMP_META[sg.k][1]}"></span>${COMP_META[sg.k][0]} <b class="num">${sg.pct.toFixed(0)}%</b></span>`
  ).join('');
  return `<div class="comp-bar">${bar}</div><div class="comp-legend">${legend}</div>`;
}

export function buildSkillsHTML(analysis) {
  if (!analysis.ok) {
    return `<div class="skills-empty">${esc(analysis.reason)}</div>`;
  }
  const parts = [];

  parts.push(`<svg width="0" height="0" style="position:absolute"><defs>
    <linearGradient id="corner-grad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#64ffda"/><stop offset="100%" stop-color="#00c6ff"/>
    </linearGradient></defs></svg>`);

  if (analysis.sampleIntervalS > 3.5) {
    parts.push(`<div class="skills-warn">⚠️ This GPX logs a point every ~${analysis.sampleIntervalS.toFixed(0)}s, which is coarse for skill analysis. A 1-second logging interval gives much sharper feedback.</div>`);
  }

  const scoreKeys = Object.keys(analysis.scores).filter(k => Number.isFinite(analysis.scores[k]));
  if (scoreKeys.length >= 3) {
    const overall = Math.round(scoreKeys.reduce((s, k) => s + analysis.scores[k], 0) / scoreKeys.length);
    const grade = GRADE_BANDS.find(([min]) => overall >= min)[1];

    const meters = scoreKeys.map(k => {
      const v = analysis.scores[k];
      const caps = METER_CAPS[k];
      const cap = v >= 70 ? caps.hi : v >= 45 ? caps.mid : caps.lo;
      return `<div class="skill-meter">
        <div class="skill-meter-row">
          <span class="skill-meter-label">${AXIS_LABELS[k]}</span>
          <span class="skill-meter-value num">${v}</span>
        </div>
        <div class="skill-meter-track"><div class="skill-meter-fill" style="width:${v}%"></div></div>
        <div class="skill-meter-cap">${cap}</div>
      </div>`;
    }).join('');

    const debrief = buildDebrief(analysis.scores);
    parts.push(`<div class="debrief-card">
      <div class="skills-headline">
        <span class="skills-headline-score num">${overall}</span>
        <span class="skills-headline-text">
          <span class="skills-headline-label">RIDER SCORE</span>
          <span class="rider-grade">${grade}</span>
        </span>
      </div>
      ${debrief ? `<div class="debrief-verdict">${debrief.verdict}</div>
      <div class="debrief-next">${debrief.next}</div>` : ''}
      ${compositionBarHTML(analysis.composition)}
    </div>
    <div class="skills-hero">
      <div class="radar-panel"><canvas id="riderSkillsRadar"></canvas></div>
      <div class="meters-panel">${meters}</div>
    </div>`);
  } else {
    parts.push(`<div class="skills-empty">Not enough corners and braking events in this ride for technique scores. The corners found are below.</div>`);
  }

  if (analysis.brakeZones.length) {
    const peak = Math.min(...analysis.brakeZones.map(z => z.peakDecel));
    const meanSmooth = analysis.brakeZones.reduce((s, z) => s + z.smoothness, 0) / analysis.brakeZones.length;
    const verdict = meanSmooth >= 70 ? 'progressive and controlled'
      : meanSmooth >= 45 ? 'mostly progressive, occasionally grabby'
      : 'abrupt; work on squeezing, not snatching';
    parts.push(`<div class="braking-strip">
      <span class="braking-strip-item">🛑 <b class="num">${analysis.brakeZones.length}</b> braking zones</span>
      <span class="braking-strip-item">Hardest <b class="num">${(Math.abs(peak) / G).toFixed(2)}</b> g</span>
      <span class="braking-strip-item">Feel: ${verdict}</span>
    </div>`);
  }

  const top = [...analysis.corners].sort((x, y) => y.maxLatG - x.maxLatG).slice(0, 10);
  if (top.length) {
    parts.push(`<h4 class="corners-heading">Top corners <span class="corners-heading-sub">by lateral load. Tap Jump to relive one.</span></h4>`);
    parts.push('<div class="corners-grid">');
    parts.push(top.map((c, i) => `
      <div class="corner-card${i >= 3 ? ' corner-hidden' : ''}">
        ${cornerGlyphSVG(c.sweepDeg, c.radiusM)}
        <div class="corner-main">
          <div class="corner-head">
            <span class="corner-rank num">${String(i + 1).padStart(2, '0')}</span>
            <span class="corner-title">Corner ${String(i + 1).padStart(2, '0')}</span>
            <button class="corner-jump" data-tapex="${c.tApex.getTime()}">↗ Replay</button>
          </div>
          <div class="corner-speeds">
            <span class="cs"><span class="cs-label">IN</span><span class="cs-val num">${c.entryKmh.toFixed(0)}</span></span>
            <span class="cs-arrow">›</span>
            <span class="cs cs-apex"><span class="cs-label">APEX</span><span class="cs-val num">${c.apexKmh.toFixed(0)}</span></span>
            <span class="cs-arrow">›</span>
            <span class="cs"><span class="cs-label">OUT</span><span class="cs-val num">${c.exitKmh.toFixed(0)}</span></span>
            <span class="cs-unit">km/h</span>
          </div>
          <div class="corner-chips">
            ${c.tags.map(t => `<span class="chip ${TONE_CLASS[t.tone] || 'chip-neutral'}">${esc(t.label)}</span>`).join('')}
          </div>
          ${c.focus ? `<div class="corner-focus">💡 ${esc(c.focus)}</div>` : ''}
          <div class="corner-meta">${c.sweepDeg.toFixed(0)}° sweep · r≈${c.radiusM.toFixed(0)} m · lean ~${c.leanDeg.toFixed(0)}° · ${c.maxLatG.toFixed(2)} g</div>
        </div>
      </div>`).join(''));
    parts.push('</div>');
    if (top.length > 3) {
      parts.push(`<button class="show-all-corners" data-count="${top.length}">Show all ${top.length} corners</button>`);
    }
  } else {
    parts.push('<div class="skills-empty">No significant corners detected in this ride.</div>');
  }

  return parts.join('\n');
}

// Thin DOM wrapper: injects HTML, wires Jump buttons, draws the technique radar
export function renderRiderSkills(analysis, opts) {
  const container = document.getElementById(opts.containerId);
  if (!container) return;
  container.innerHTML = buildSkillsHTML(analysis);
  container.querySelectorAll('.corner-jump').forEach(btn => {
    btn.addEventListener('click', () => opts.jumpToTime(new Date(+btn.dataset.tapex)));
  });

  const showAll = container.querySelector('.show-all-corners');
  if (showAll) {
    showAll.addEventListener('click', () => {
      container.querySelectorAll('.corner-hidden').forEach(el => el.classList.remove('corner-hidden'));
      showAll.remove();
    });
  }

  const canvas = container.querySelector('#riderSkillsRadar');
  if (!canvas || typeof Chart === 'undefined') return;
  const scoreKeys = Object.keys(analysis.scores).filter(k => Number.isFinite(analysis.scores[k]));
  if (window.riderSkillsRadarChart && typeof window.riderSkillsRadarChart.destroy === 'function') {
    window.riderSkillsRadarChart.destroy();
  }
  window.riderSkillsRadarChart = new Chart(canvas.getContext('2d'), {
    type: 'radar',
    data: {
      labels: scoreKeys.map(k => AXIS_LABELS[k]),
      datasets: [{
        data: scoreKeys.map(k => analysis.scores[k]),
        backgroundColor: 'rgba(100,255,218,0.20)',
        borderColor: '#64ffda',
        borderWidth: 2.5,
        pointBackgroundColor: '#00c6ff',
        pointBorderColor: '#fff',
        pointRadius: 4.5
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        r: {
          min: 0, max: 100,
          ticks: { stepSize: 25, display: false },
          grid: { color: 'rgba(100,255,218,0.14)' },
          angleLines: { color: 'rgba(100,255,218,0.14)' },
          pointLabels: {
            color: '#c5d1e3',
            font: { size: 14, weight: '600', family: "'Rajdhani','Segoe UI',Arial,sans-serif" }
          }
        }
      },
      plugins: {
        legend: { display: false },
        tooltip: { callbacks: { label: ctx => ` ${ctx.raw} / 100` } }
      }
    }
  });
}
