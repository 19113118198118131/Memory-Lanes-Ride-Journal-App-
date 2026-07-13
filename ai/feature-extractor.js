// ===============================
// Memory Lanes - ai/feature-extractor.js
// Turns a completed ride into a compact, comparable feature record. This is
// the "Standard Ride Feature Record" from the AI plan: it ASSEMBLES numbers
// the deterministic engine already produced (riderskills analysis + the ride's
// distance/duration/elevation) rather than computing anything new, so it stays
// cheap and stays consistent with what the coach shows.
// ===============================

import { FEATURE_SCHEMA_VERSION, MATCH_FEATURES } from './feature-schema.js?v=86';

function num(v) { return Number.isFinite(v) ? v : null; }
function mean(arr) { return arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : null; }

// Bearing change per km along a GPS track: the same signal the planner engine
// scores candidates on, so a ride's "turnsPerKm" is comparable to a
// candidate's. Points are {lat, lng}.
function turnsPerKmFromTrack(points, totalKm) {
  if (!Array.isArray(points) || points.length < 3 || !totalKm) return null;
  const toRad = d => d * Math.PI / 180, toDeg = r => r * 180 / Math.PI;
  const bearing = (a, b) => {
    const lat1 = toRad(a.lat), lat2 = toRad(b.lat), dLng = toRad(b.lng - a.lng);
    const y = Math.sin(dLng) * Math.cos(lat2);
    const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
    return (toDeg(Math.atan2(y, x)) + 360) % 360;
  };
  let turns = 0, prev = null;
  for (let i = 1; i < points.length; i++) {
    const b = bearing(points[i - 1], points[i]);
    if (prev != null) {
      let d = Math.abs(b - prev);
      if (d > 180) d = 360 - d;
      if (d > 8) turns++;
    }
    prev = b;
  }
  return turns / totalKm;
}

/**
 * Build a ride feature record.
 * @param {object} analysis  riderskills analyzeRide() result (may be {ok:false})
 * @param {object} meta      { distanceKm, durationMin, elevationGainM, points }
 * @returns {object} feature record (always has schemaVersion + route block)
 */
export function extractRideFeatures(analysis, meta = {}) {
  const distanceKm = num(meta.distanceKm);
  const durationMin = num(meta.durationMin);
  const elevationGainM = num(meta.elevationGainM);
  const avgSpeedKmh = distanceKm && durationMin ? distanceKm / (durationMin / 60) : null;

  const corners = analysis && analysis.ok && Array.isArray(analysis.corners) ? analysis.corners : [];
  const cornerCount = corners.length || null;
  const avgCornerRadiusM = corners.length ? Math.round(mean(corners.map(c => c.radiusM).filter(Number.isFinite))) : null;

  // Prefer the true track geometry; fall back to corner count over distance.
  let turnsPerKm = turnsPerKmFromTrack(meta.points, distanceKm);
  if (turnsPerKm == null && cornerCount && distanceKm) turnsPerKm = cornerCount / distanceKm;
  turnsPerKm = turnsPerKm != null ? +turnsPerKm.toFixed(2) : null;

  const scores = (analysis && analysis.ok && analysis.scores) ? analysis.scores : {};

  return {
    schemaVersion: FEATURE_SCHEMA_VERSION,
    route: {
      distanceKm: distanceKm != null ? +distanceKm.toFixed(1) : null,
      durationMin: durationMin != null ? Math.round(durationMin) : null,
      elevationGainM: elevationGainM != null ? Math.round(elevationGainM) : null,
      avgSpeedKmh: avgSpeedKmh != null ? +avgSpeedKmh.toFixed(1) : null,
      turnsPerKm,
      cornerCount,
      avgCornerRadiusM
    },
    technique: {
      cornerEntry: num(scores.cornerEntry),
      exitDrive: num(scores.exitDrive),
      brakingSmoothness: num(scores.brakingSmoothness),
      throttleSmoothness: num(scores.throttleSmoothness),
      consistency: num(scores.consistency)
    }
  };
}

// Pull the shared match vector out of a stored ride feature record.
// Returns null if any required dimension is missing (that ride can't be a
// KNN neighbour, and that's fine - we just use the ones that are complete).
export function matchVectorFromRide(features) {
  if (!features || !features.route) return null;
  const v = MATCH_FEATURES.map(f => num(features.route[f.key]));
  return v.every(x => x != null) ? v : null;
}

// Same vector, from a planner-engine candidate object.
export function matchVectorFromCandidate(candidate) {
  if (!candidate) return null;
  const map = {
    distanceKm: candidate.distanceKm,
    elevationGainM: candidate.elevationGainM,
    turnsPerKm: candidate.stats ? candidate.stats.turnsPerKm : null
  };
  const v = MATCH_FEATURES.map(f => num(map[f.key]));
  return v.every(x => x != null) ? v : null;
}
