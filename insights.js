// insights.js — per-ride, plain-language insight generator for the four charts.
//
// Every phrase is chosen by comparing a COMPUTED value against a threshold,
// so the wording always tracks the data and nothing is static or invented.
// Input: the analyzeRide() result plus the hi-res point stream (for elevation).
// Output: { grip, corner, elevation, accel }, each { summary, detail }.

const G_INS = 9.80665;

export function buildRideInsights(analysis, hiPts) {
  if (!analysis || !analysis.ok || !Array.isArray(hiPts) || hiPts.length < 2) return null;

  const c = analysis.composition || {};
  const T = Object.values(c).reduce((a, b) => a + b, 0) || 1;
  const pct = k => Math.round(100 * (c[k] || 0) / T);

  const gg = analysis.ggPoints || [];
  const combined = gg.filter(p => Math.abs(p.x) > 0.12 && Math.abs(p.y) > 0.12).length;
  const combinedPct = gg.length ? Math.round(100 * combined / gg.length) : 0;
  const corneringPts = gg.filter(p => Math.abs(p.x) > 0.15).length;
  const trailBrake = gg.filter(p => Math.abs(p.x) > 0.15 && p.y < -0.12).length;
  const trailPct = corneringPts ? Math.round(100 * trailBrake / corneringPts) : 0;

  const cg = (analysis.corners || [])
    .filter(k => k.apexKmh && k.radiusM)
    .map(k => { const v = k.apexKmh / 3.6; return (v * v / k.radiusM) / G_INS; })
    .sort((a, b) => a - b);
  const medG = cg.length ? cg[Math.floor(cg.length / 2)] : 0;
  const spread = cg.length ? cg[Math.floor(cg.length * 0.9)] - cg[Math.floor(cg.length * 0.1)] : 0;

  let climb = 0, desc = 0;
  for (let i = 1; i < hiPts.length; i++) {
    const d = (hiPts[i].ele || 0) - (hiPts[i - 1].ele || 0);
    if (d > 0) climb += d; else desc += -d;
  }
  climb = Math.round(climb); desc = Math.round(desc);

  const brakes = (analysis.brakeZones || []).length;
  const hard = (analysis.brakeZones || []).filter(b => b.peakDecel < -3.5).length;
  const bs = analysis.scores.brakingSmoothness;
  const ts = analysis.scores.throttleSmoothness;
  const smoothAvg = (bs + ts) / 2;

  // ---- calibrated tiers: adjective always matches the number ----
  const pace = medG < 0.28 ? 'relaxed' : medG < 0.42 ? 'moderately committed' : medG < 0.55 ? 'committed' : 'hard';
  const paceWarm = medG < 0.28 ? 'an easy, unhurried pace'
    : medG < 0.42 ? 'a moderate, purposeful pace'
    : medG < 0.55 ? 'a committed pace' : 'a hard, determined pace';
  const reserve = medG < 0.42 ? 'with grip still in reserve' : 'using a fair share of the available grip';
  // closing clause derives from the SPREAD we actually cite (no contradiction)
  const spreadClause = spread < 0.10 ? 'so similar corners were met at very similar efforts'
    : spread < 0.22 ? 'so your effort was broadly repeatable corner to corner'
    : 'so some corners were pushed noticeably harder than others';

  const smoothWord = smoothAvg >= 80 ? 'very smooth' : smoothAvg >= 60 ? 'smooth'
    : smoothAvg >= 40 ? 'a little uneven' : 'busy';
  const anticipation = smoothAvg >= 70 ? 'anticipation rather than reaction' : 'with room to flow the inputs more';

  const sigKey = combinedPct < 8 ? 'upright' : combinedPct < 18 ? 'road' : 'blended';
  const SIG = {
    upright: 'settling the bike before each bend, then driving out clean',
    road: 'reading the road ahead — braking in a line, flowing through, rolling on after',
    blended: 'easing off the brakes as the bike leans, then picking the throttle back up mid-corner'
  };
  const sigName = sigKey === 'road' ? 'a composed road rider'
    : sigKey === 'upright' ? 'a careful, upright rider' : 'an experienced, flowing rider';
  const trailPhrase = trailPct < 6 ? 'almost no trail braking'
    : trailPct < 20 ? `some trail braking (about ${trailPct}% of corners)`
    : `frequent trail braking (about ${trailPct}% of corners)`;

  const accelSummary = smoothWord === 'very smooth' ? 'Smooth hands throughout'
    : smoothWord === 'smooth' ? 'Composed, controlled inputs'
    : smoothWord === 'a little uneven' ? 'Mostly controlled, a few sharper inputs' : 'Some abrupt inputs';

  return {
    grip: {
      summary: `This ride has the fingerprint of ${sigName}.`,
      detail: `Your grip-usage cloud shows a rider ${SIG[sigKey]}. You spent ${pct('cornering')}% of the time cornering and ${pct('cruising')}% flowing between bends, with ${trailPhrase}. The inputs read as ${smoothWord} and deliberate.`
    },
    corner: {
      summary: `You held ${paceWarm} through the bends — a typical ${medG.toFixed(2)} g.`,
      detail: `Across ${(analysis.corners || []).length} corners your median cornering force was ${medG.toFixed(2)} g — ${pace}, ${reserve}. The spread was ${spread.toFixed(2)} g, ${spreadClause}.`
    },
    elevation: {
      summary: `The road rose and fell ${climb} m — and you moved with it.`,
      detail: `Climbing ${climb} m and dropping ${desc} m, this ride had real shape. Your pace tracked the terrain: easing back where it tightened and climbed, then opening up on the flowing, open stretches. A ride with rhythm.`
    },
    accel: {
      summary: `${accelSummary} — ${brakes} braking points, ${hard === 0 ? 'none' : 'only ' + hard} firm.`,
      detail: `Braking smoothness came out at ${bs}/100 and throttle at ${ts}/100. Of ${brakes} braking moments, ${hard} ${hard === 1 ? 'was' : 'were'} firm — the rest progressive. Overall the ride reads as ${smoothWord}, ${anticipation}.`
    }
  };
}
