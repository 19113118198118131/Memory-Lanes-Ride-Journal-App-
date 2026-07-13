// ===============================
// Memory Lanes - ai/recommender.js
// "Routes you'll probably enjoy": a small, dependency-free weighted KNN over
// the rider's OWN rated rides. Given a set of freshly generated planner
// candidates, it predicts how much this rider will enjoy each one and explains
// why, in plain language, from the features that actually drove the match.
//
// Why hand-rolled and not mljs: KNN over a few dozen rides is a few lines of
// arithmetic. Keeping it native means no model download, it works offline in
// the PWA, and it degrades honestly when data is thin. The value here is the
// feature design + the explanation, not the library.
// ===============================

import { MATCH_FEATURES, MIN_LABELLED_RIDES } from './feature-schema.js?v=83';
import { matchVectorFromRide, matchVectorFromCandidate } from './feature-extractor.js?v=83';

// Per-feature mean/std across the rated rides, so no single dimension (e.g.
// distance in the tens of km) dominates a dimension measured in single digits.
function standardizer(vectors) {
  const dims = MATCH_FEATURES.length;
  const mean = new Array(dims).fill(0);
  const std = new Array(dims).fill(0);
  vectors.forEach(v => v.forEach((x, i) => { mean[i] += x; }));
  mean.forEach((_, i) => { mean[i] /= vectors.length; });
  vectors.forEach(v => v.forEach((x, i) => { std[i] += (x - mean[i]) ** 2; }));
  std.forEach((_, i) => { std[i] = Math.sqrt(std[i] / vectors.length) || 1; }); // avoid /0 on a constant dim
  return { mean, std };
}

function zApply(vec, { mean, std }) {
  // Feature weights fold in here: a heavier weight stretches that axis, so
  // closeness on it counts for more in the Euclidean distance.
  return vec.map((x, i) => ((x - mean[i]) / std[i]) * MATCH_FEATURES[i].weight);
}

function euclid(a, b) {
  return Math.sqrt(a.reduce((s, _, i) => s + (a[i] - b[i]) ** 2, 0));
}

/**
 * @param {Array} ratedRides  [{ features, enjoyment }] - enjoyment 1..5
 * @returns {object|null} a scorer, or null when there isn't enough to learn from
 */
export function buildRecommender(ratedRides) {
  const clean = (ratedRides || [])
    .map(r => ({ vec: matchVectorFromRide(r.features), enjoyment: r.enjoyment }))
    .filter(r => r.vec && Number.isFinite(r.enjoyment));

  if (clean.length < MIN_LABELLED_RIDES) {
    return { ready: false, ratedCount: clean.length, needed: MIN_LABELLED_RIDES };
  }

  const norm = standardizer(clean.map(r => r.vec));
  const neighbours = clean.map(r => ({ z: zApply(r.vec, norm), enjoyment: r.enjoyment, raw: r.vec }));
  // Averages of the rides this rider rated highly (>=4), for the "why" text.
  const liked = clean.filter(r => r.enjoyment >= 4).map(r => r.vec);
  const likedMean = liked.length
    ? MATCH_FEATURES.map((_, i) => liked.reduce((s, v) => s + v[i], 0) / liked.length)
    : null;

  const k = Math.min(5, neighbours.length);

  function score(candidate) {
    const vec = matchVectorFromCandidate(candidate);
    if (!vec) return null;
    const z = zApply(vec, norm);

    const ranked = neighbours
      .map(n => ({ d: euclid(z, n.z), enjoyment: n.enjoyment }))
      .sort((a, b) => a.d - b.d)
      .slice(0, k);

    // Inverse-distance weighted mean enjoyment of the k nearest rated rides.
    let wSum = 0, eSum = 0;
    ranked.forEach(n => { const w = 1 / (0.35 + n.d); wSum += w; eSum += w * n.enjoyment; });
    const predicted = eSum / wSum;                 // 1..5
    const matchPct = Math.round(((predicted - 1) / 4) * 100); // 0..100

    // Confidence: closer neighbours + more rated rides = more trustworthy.
    const nearest = ranked[0] ? ranked[0].d : Infinity;
    const confidence = nearest < 1 ? 'high' : nearest < 2.2 ? 'medium' : 'low';

    return { matchPct, predicted: +predicted.toFixed(2), confidence, reasons: reasonsFor(vec, likedMean) };
  }

  return { ready: true, ratedCount: clean.length, score };
}

// Turn "close on these features to your favourites" into readable bullets.
function reasonsFor(vec, likedMean) {
  if (!likedMean) return ['Matched against the rides you have rated so far'];
  const out = [];
  MATCH_FEATURES.forEach((f, i) => {
    const cand = vec[i], fav = likedMean[i];
    if (!Number.isFinite(cand) || !Number.isFinite(fav) || fav === 0) return;
    const ratio = cand / fav;
    if (ratio >= 0.85 && ratio <= 1.15) {
      out.push(`Similar ${f.label} to rides you rated highly`);
    } else if (f.key === 'turnsPerKm') {
      out.push(ratio > 1.15 ? 'More corners than your usual favourites' : 'Calmer, fewer corners than your usual favourites');
    } else if (f.key === 'distanceKm') {
      out.push(ratio > 1.15 ? 'Longer than your usual ride length' : 'Shorter than your usual ride length');
    } else if (f.key === 'elevationGainM') {
      out.push(ratio > 1.15 ? 'Hillier than your favourites' : 'Flatter than your favourites');
    }
  });
  // Lead with the "similar" reasons; keep it to the three strongest.
  return out.sort((a, b) => (a.startsWith('Similar') ? -1 : 1) - (b.startsWith('Similar') ? -1 : 1)).slice(0, 3);
}
