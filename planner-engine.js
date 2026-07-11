// ===============================
// Memory Lanes Ride Journal - planner-engine.js
// Candidate route generation + scoring for loop rides (MVP2).
//
// Turns "start point + time available + riding mood" into several distinct
// loop route candidates, each scored on how well it fits the time goal, how
// curvy/engaging it is, how likely it is to run through built-up areas, and
// how much it doubles back on itself.
//
// Honesty notes (things this engine estimates rather than knows for sure):
// - "Urban" exposure is approximated from OSRM turn/junction density, not
//   real road-classification data (the public OSRM demo API doesn't expose
//   road class per step). More junctions per km reads as more built-up.
// - There's no scenic/POI data source wired up yet, so "scenic" mood reuses
//   the low-urban-exposure signal as a rough proxy for quiet, pleasant roads
//   rather than actually detecting coastlines, lookouts, etc.
// - Ride time is estimated from distance / assumed mood pace, not from
//   OSRM's raw driving-time estimate (which assumes ordinary car speeds,
//   not a recreational motorcycle pace).
// No dependencies, no DOM access - pure functions plus fetch().
// ===============================

export const MOOD_SPEED_KMH = {
  flowing: 62,
  twisty: 48,
  scenic: 52,
  relaxed: 50
};

export const MOOD_LABELS = {
  flowing: 'Flowing',
  twisty: 'Twisty',
  scenic: 'Scenic',
  relaxed: 'Relaxed'
};

// Weights for the 4 factors this MVP can actually compute (goal fit,
// curvature, low-urban-exposure, low-repetition). Each mood biases the mix
// toward what that kind of ride cares about most.
const MOOD_WEIGHTS = {
  flowing: { goalFit: 0.35, curvature: 0.20, urbanLow: 0.30, repetitionLow: 0.15 },
  twisty:  { goalFit: 0.30, curvature: 0.40, urbanLow: 0.20, repetitionLow: 0.10 },
  scenic:  { goalFit: 0.35, curvature: 0.20, urbanLow: 0.35, repetitionLow: 0.10 },
  relaxed: { goalFit: 0.40, curvature: 0.10, urbanLow: 0.35, repetitionLow: 0.15 }
};

export function targetDistanceKm(minutes, mood) {
  const speed = MOOD_SPEED_KMH[mood] || 50;
  return (minutes / 60) * speed;
}

export function formatMinutes(min) {
  const m = Math.round(min);
  const h = Math.floor(m / 60), rem = m % 60;
  return h > 0 ? `${h}h ${rem}m` : `${rem}m`;
}

// ---------- Geometry ----------
function toRad(d) { return d * Math.PI / 180; }
function toDeg(r) { return r * 180 / Math.PI; }

// Forward geodesic: point at `bearingDeg` and `distKm` from (lat, lng).
export function destPoint(lat, lng, bearingDeg, distKm) {
  const R = 6371;
  const brng = toRad(bearingDeg);
  const dR = distKm / R;
  const lat1 = toRad(lat), lng1 = toRad(lng);
  const lat2 = Math.asin(Math.sin(lat1) * Math.cos(dR) + Math.cos(lat1) * Math.sin(dR) * Math.cos(brng));
  const lng2 = lng1 + Math.atan2(
    Math.sin(brng) * Math.sin(dR) * Math.cos(lat1),
    Math.cos(dR) - Math.sin(lat1) * Math.sin(lat2)
  );
  return { lat: toDeg(lat2), lng: ((toDeg(lng2) + 540) % 360) - 180 };
}

function bearingBetween(a, b) {
  const lat1 = toRad(a[0]), lat2 = toRad(b[0]);
  const dLng = toRad(b[1] - a[1]);
  const y = Math.sin(dLng) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

function haversineKm(a, b) {
  const R = 6371;
  const dLat = toRad(b[0] - a[0]), dLng = toRad(b[1] - a[1]);
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a[0])) * Math.cos(toRad(b[0])) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

function sampleEvery(arr, everyN) {
  if (everyN <= 1) return arr;
  return arr.filter((_, i) => i % everyN === 0);
}

// ---------- Anchor patterns (what makes the 3 candidates genuinely different shapes) ----------
// Each pattern is a list of bearing offsets (from a random base bearing) and
// a radius multiplier, applied against the target-distance-derived radius.
const ANCHOR_PATTERNS = [
  { label: 'Compact Loop', offsets: [30, 150], radiusMul: 0.62 },
  { label: 'Wide Loop', offsets: [-20, 110, 230], radiusMul: 1.0 },
  { label: 'Directional Loop', offsets: [55, 105], radiusMul: 0.85 }
];

function buildAnchors(origin, baseBearing, targetKm, pattern, jitter = 0) {
  // Real road networks aren't circles - a loop's "reach" from its start is
  // roughly a quarter to a fifth of its total ridden distance, not distance / 2pi.
  const radiusKm = Math.min(150, Math.max(6, (targetKm / 4.5) * pattern.radiusMul));
  return pattern.offsets.map(off => {
    const bearing = baseBearing + off + jitter;
    return destPoint(origin.lat, origin.lng, bearing, radiusKm);
  });
}

// ---------- OSRM ----------
async function osrmRoute(coordPairs, signal) {
  const coordStr = coordPairs.map(p => `${p.lng},${p.lat}`).join(';');
  const url = `https://router.project-osrm.org/route/v1/driving/${coordStr}?overview=full&geometries=geojson&steps=true`;
  const resp = await fetch(url, { signal });
  if (!resp.ok) throw new Error('routing failed');
  const data = await resp.json();
  if (data.code !== 'Ok' || !data.routes || !data.routes[0]) throw new Error('no route found');
  const route = data.routes[0];
  const coords = route.geometry.coordinates.map(c => [c[1], c[0]]);
  const steps = (route.legs || []).flatMap(leg => leg.steps || []);
  return { coords, distanceKm: route.distance / 1000, durationMinRaw: route.duration / 60, stepCount: steps.length, steps };
}

// The public OSRM API doesn't expose road class, but sustained high average
// speed on a step is a reasonable stand-in for "motorway-grade road" -
// derived from the routing engine's own numbers rather than guessed from
// road names.
function motorwayEstimate(steps) {
  let motorwayKm = 0;
  for (const s of steps) {
    if (!s.distance || !s.duration) continue;
    const kmh = (s.distance / 1000) / (s.duration / 3600);
    if (kmh > 90) motorwayKm += s.distance / 1000;
  }
  return { motorwayKm, score: Math.max(0, 100 - motorwayKm * 4) };
}

async function estimateElevationGain(coords, signal) {
  if (coords.length < 2) return 0;
  const sampled = sampleEvery(coords, Math.max(1, Math.floor(coords.length / 100)));
  const lats = sampled.map(c => c[0].toFixed(5)).join(',');
  const lons = sampled.map(c => c[1].toFixed(5)).join(',');
  const url = `https://api.open-meteo.com/v1/elevation?latitude=${lats}&longitude=${lons}`;
  const resp = await fetch(url, { signal });
  if (!resp.ok) throw new Error('elevation lookup failed');
  const data = await resp.json();
  const elevations = data.elevation || [];
  let gain = 0;
  for (let i = 1; i < elevations.length; i++) {
    const diff = elevations[i] - elevations[i - 1];
    if (diff > 1.5) gain += diff;
  }
  return Math.round(gain);
}

// ---------- Scoring ----------
function curvatureScore(coords) {
  if (coords.length < 3) return { turnCount: 0, turnsPerKm: 0, score: 0 };
  const pts = sampleEvery(coords, Math.max(1, Math.floor(coords.length / 400))); // cap cost on very dense geometries
  let turnCount = 0;
  let prevBearing = null;
  for (let i = 1; i < pts.length; i++) {
    if (haversineKm(pts[i - 1], pts[i]) < 0.02) continue; // skip near-duplicate points
    const b = bearingBetween(pts[i - 1], pts[i]);
    if (prevBearing != null) {
      let delta = Math.abs(b - prevBearing);
      if (delta > 180) delta = 360 - delta;
      if (delta > 8) turnCount++;
    }
    prevBearing = b;
  }
  const totalKm = pts.reduce((sum, p, i) => i ? sum + haversineKm(pts[i - 1], p) : sum, 0) || 1;
  const turnsPerKm = turnCount / totalKm;
  return { turnCount, turnsPerKm, score: Math.max(0, Math.min(100, turnsPerKm * 12)) };
}

function urbanScore(stepCount, distanceKm) {
  const stepsPerKm = stepCount / Math.max(0.1, distanceKm);
  // ~1 step/km reads as open road; 6+ steps/km reads as dense/urban.
  const score = Math.max(0, Math.min(100, 100 - (stepsPerKm - 1) * 15));
  return { stepsPerKm, score };
}

function repetitionScore(coords) {
  if (coords.length < 6) return { overlapPct: 0, score: 100 };
  const half = Math.floor(coords.length / 2);
  const outbound = sampleEvery(coords.slice(0, half), Math.max(1, Math.floor(half / 60)));
  const inbound = sampleEvery(coords.slice(half), Math.max(1, Math.floor((coords.length - half) / 60)));
  let overlapping = 0;
  for (const p of inbound) {
    let minD = Infinity;
    for (const q of outbound) {
      const d = haversineKm(p, q);
      if (d < minD) minD = d;
      if (minD < 0.08) break;
    }
    if (minD < 0.08) overlapping++; // within ~80m of some outbound point
  }
  const overlapPct = Math.round((overlapping / inbound.length) * 100);
  return { overlapPct, score: Math.max(0, 100 - overlapPct) };
}

function goalFitScore(estMin, targetMin) {
  const pctOff = Math.abs(estMin - targetMin) / targetMin;
  if (pctOff <= 0.05) return 100;
  if (pctOff <= 0.10) return 80;
  if (pctOff <= 0.20) return 60;
  if (pctOff <= 0.35) return 35;
  return 10;
}

function weightedTotal(parts, mood) {
  const w = MOOD_WEIGHTS[mood] || MOOD_WEIGHTS.flowing;
  return Math.round(
    parts.goalFit * w.goalFit +
    parts.curvature * w.curvature +
    parts.urbanLow * w.urbanLow +
    parts.repetitionLow * w.repetitionLow
  );
}

// ---------- Candidate assembly ----------
async function buildCandidate(origin, baseBearing, pattern, targetMinutes, mood, avoidMotorway, signal) {
  let anchors = buildAnchors(origin, baseBearing, targetDistanceKm(targetMinutes, mood), pattern);
  let routed = null;
  for (let attempt = 0; attempt < 2 && !routed; attempt++) {
    try {
      const coordPairs = [origin, ...anchors, origin];
      routed = await osrmRoute(coordPairs, signal);
    } catch (e) {
      if (e.name === 'AbortError') throw e;
      // Retry once with jittered anchors (an anchor may have landed somewhere unroutable, e.g. open water).
      anchors = buildAnchors(origin, baseBearing + (Math.random() * 30 - 15), targetDistanceKm(targetMinutes, mood), pattern, 10);
    }
  }
  if (!routed) return null;

  const elevationGainM = await estimateElevationGain(routed.coords, signal).catch(() => null);
  const estimatedMinutes = (routed.distanceKm / (MOOD_SPEED_KMH[mood] || 50)) * 60;

  const curv = curvatureScore(routed.coords);
  const urban = urbanScore(routed.stepCount, routed.distanceKm);
  const rep = repetitionScore(routed.coords);
  const goalFit = goalFitScore(estimatedMinutes, targetMinutes);
  const motorway = motorwayEstimate(routed.steps);

  let total = weightedTotal({ goalFit, curvature: curv.score, urbanLow: urban.score, repetitionLow: rep.score }, mood);
  // Only factored in when the rider actually asked to avoid motorways - this
  // is a real signal (sustained high step speed) but a rough one, so it's
  // kept as a modest blend rather than a hard veto.
  if (avoidMotorway) total = Math.round(total * 0.85 + motorway.score * 0.15);

  const scores = {
    goalFit, curvature: curv.score, urbanLow: urban.score, repetitionLow: rep.score,
    total
  };

  return {
    label: pattern.label,
    waypoints: [origin, ...anchors, origin],
    coords: routed.coords,
    distanceKm: routed.distanceKm,
    estimatedMinutes,
    elevationGainM,
    stats: { turnCount: curv.turnCount, turnsPerKm: curv.turnsPerKm, stepsPerKm: urban.stepsPerKm, overlapPct: rep.overlapPct, motorwayKm: motorway.motorwayKm },
    scores
  };
}

// Picks a short, honest "what stands out about this one" tag by comparing
// candidates against each other - no invented scenery claims.
function tagCandidates(candidates) {
  if (candidates.length < 2) return candidates;
  const byCurv = [...candidates].sort((a, b) => b.stats.turnsPerKm - a.stats.turnsPerKm);
  const byUrban = [...candidates].sort((a, b) => b.scores.urbanLow - a.scores.urbanLow);
  const byGoal = [...candidates].sort((a, b) => b.scores.goalFit - a.scores.goalFit);
  candidates.forEach(c => {
    if (c === byCurv[0] && c.stats.turnsPerKm > byCurv[1].stats.turnsPerKm * 1.1) c.tag = 'More twisty';
    else if (c === byUrban[0] && c.scores.urbanLow > byUrban[1].scores.urbanLow + 5) c.tag = 'Quietest roads';
    else if (c === byGoal[0] && c.scores.goalFit > byGoal[1].scores.goalFit) c.tag = 'Closest to your time';
    else c.tag = c.label;
  });
  return candidates;
}

/**
 * Generate up to 3 distinct loop route candidates starting and ending at `origin`.
 * @param {{lat:number, lng:number}} origin
 * @param {{targetMinutes:number, mood:string, avoidMotorway?:boolean}} opts
 * @param {AbortSignal} [signal]
 * @returns {Promise<Array>} scored candidates, best-first
 */
export async function generateLoopCandidates(origin, { targetMinutes, mood, avoidMotorway = false }, signal) {
  const baseBearing = Math.random() * 360;
  const results = await Promise.allSettled(
    ANCHOR_PATTERNS.map(pattern => buildCandidate(origin, baseBearing, pattern, targetMinutes, mood, avoidMotorway, signal))
  );
  const candidates = results
    .filter(r => r.status === 'fulfilled' && r.value)
    .map(r => r.value)
    .sort((a, b) => b.scores.total - a.scores.total);
  return tagCandidates(candidates);
}

export function buildWhyBullets(candidate, mood) {
  const bullets = [];
  const { turnCount, turnsPerKm, stepsPerKm } = candidate.stats;
  bullets.push(`${turnCount} notable direction changes (~${turnsPerKm.toFixed(1)} per km)`);
  const urbanLabel = stepsPerKm < 2 ? 'mostly open road' : stepsPerKm < 4 ? 'a moderate mix of junctions' : 'frequent junctions - likely built-up in places';
  bullets.push(`~${stepsPerKm.toFixed(1)} turns/junctions per km - ${urbanLabel}`);
  bullets.push(`Estimated riding time ~${formatMinutes(candidate.estimatedMinutes)} at a ${MOOD_LABELS[mood] || mood} pace`);
  if (candidate.elevationGainM != null) bullets.push(`Elevation gain approximately ${candidate.elevationGainM} m`);
  if (candidate.stats.motorwayKm < 3) bullets.push('Little to no motorway-speed road');
  return bullets;
}

export function buildCautions(candidate, targetMinutes) {
  const cautions = [];
  if (candidate.stats.motorwayKm >= 3) cautions.push(`Approximately ${Math.round(candidate.stats.motorwayKm)} km at motorway-like speeds`);
  if (candidate.stats.overlapPct > 15) cautions.push(`~${candidate.stats.overlapPct}% of the route retraces the same road`);
  if (candidate.scores.goalFit < 60) {
    const longer = candidate.estimatedMinutes > targetMinutes;
    cautions.push(`This runs ${longer ? 'longer' : 'shorter'} than your ${formatMinutes(targetMinutes)} target`);
  }
  cautions.push('Road surface and traffic conditions are estimated, not guaranteed - always ride to conditions.');
  return cautions;
}
