// Pure simulation for Memory Lanes: Flow. This module deliberately has no DOM,
// Canvas, audio, storage, or network dependencies so a session can be replayed
// deterministically and tested with Node's built-in test runner.

export const FLOW_CONSTANTS = Object.freeze({
  worldWidth: 1000,
  worldHeight: 1600,
  roadSampleStep: 18,
  roadHalfWidth: 205,
  minimumRoadHalfWidth: 150,
  roadAheadDistance: 2600,
  baseTravelSpeed: 150,
  maximumDeltaTime: 0.05,
  initialFlow: 68,
  quickDuration: 90,
  quickProtectionDuration: 35,
  maximumLateralVelocity: 760,
  maximumLateralAcceleration: 2300,
  steeringResponse: 16,
  steeringDamping: 7.5,
  scoreRate: 78,
  highFlowThreshold: 75,
  arriveDuration: 15,
  followDuration: 20,
  flowDuration: 40,
  landDuration: 15,
});

export const BREATHING_PATTERNS = Object.freeze({
  balanced: Object.freeze({ preset: 'balanced', inhaleDurationMs: 5000, exhaleDurationMs: 5000 }),
  settle: Object.freeze({ preset: 'settle', inhaleDurationMs: 4000, exhaleDurationMs: 6000 }),
  gentle: Object.freeze({ preset: 'gentle', inhaleDurationMs: 5000, exhaleDurationMs: 6000 }),
});

export function clamp(value, minimum, maximum) {
  return Math.min(maximum, Math.max(minimum, value));
}

function hashSeed(seed) {
  let hash = 2166136261;
  const text = String(seed);
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

export function createSeededRandom(seed) {
  let value = hashSeed(seed) || 0x6d2b79f5;
  return function random() {
    value += 0x6d2b79f5;
    let result = value;
    result = Math.imul(result ^ (result >>> 15), result | 1);
    result ^= result + Math.imul(result ^ (result >>> 7), result | 61);
    return ((result ^ (result >>> 14)) >>> 0) / 4294967296;
  };
}

function randomBetween(random, minimum, maximum) {
  return minimum + (maximum - minimum) * random();
}

function smoothstep(value) {
  const t = clamp(value, 0, 1);
  return t * t * (3 - 2 * t);
}

export function createBreathingPattern(preset = 'settle') {
  const source = BREATHING_PATTERNS[preset] || BREATHING_PATTERNS.settle;
  return {
    ...source,
    cycleDurationMs: source.inhaleDurationMs + source.exhaleDurationMs,
  };
}

export function getBreathingPhaseAtTime(pattern, elapsedMs) {
  const cycleDurationMs = Math.max(1, pattern.cycleDurationMs);
  const cycleTimeMs = ((elapsedMs % cycleDurationMs) + cycleDurationMs) % cycleDurationMs;
  const inhale = cycleTimeMs < pattern.inhaleDurationMs;
  const phaseDurationMs = inhale ? pattern.inhaleDurationMs : pattern.exhaleDurationMs;
  const phaseElapsedMs = inhale ? cycleTimeMs : cycleTimeMs - pattern.inhaleDurationMs;
  return {
    phase: inhale ? 'inhale' : 'exhale',
    phaseProgress: clamp(phaseElapsedMs / Math.max(1, phaseDurationMs), 0, 1),
    cycleIndex: Math.floor(Math.max(0, elapsedMs) / cycleDurationMs),
  };
}

export function getBreathingVisualEnvelope(breathing) {
  const progress = smoothstep(breathing.phaseProgress);
  return breathing.phase === 'inhale' ? progress : 1 - progress;
}

export function getQuickResetStage(elapsedSeconds) {
  if (elapsedSeconds < FLOW_CONSTANTS.arriveDuration) return 'arrive';
  if (elapsedSeconds < FLOW_CONSTANTS.arriveDuration + FLOW_CONSTANTS.followDuration) return 'follow';
  if (elapsedSeconds < FLOW_CONSTANTS.arriveDuration + FLOW_CONSTANTS.followDuration + FLOW_CONSTANTS.flowDuration) return 'flow';
  if (elapsedSeconds < FLOW_CONSTANTS.quickDuration) return 'land';
  return 'complete';
}

export function updateBreathingState(state) {
  const guidedElapsed = state.mode === 'quick'
    ? Math.max(0, state.elapsed - FLOW_CONSTANTS.arriveDuration)
    : state.elapsed;
  const phase = getBreathingPhaseAtTime(state.breathing.pattern, guidedElapsed * 1000);
  state.breathing.phase = phase.phase;
  state.breathing.phaseProgress = phase.phaseProgress;
  state.breathing.cycleIndex = phase.cycleIndex;
  state.breathing.visualEnvelope = getBreathingVisualEnvelope(state.breathing);
  return state.breathing;
}

export function scheduleCornerForBreathCycle(state, cycleIndex = state.breathing.cycleIndex) {
  const pattern = state.breathing.pattern;
  const cycleStartSeconds = cycleIndex * pattern.cycleDurationMs / 1000;
  return {
    cycleIndex,
    revealAtSeconds: cycleStartSeconds,
    turnInAtSeconds: cycleStartSeconds + pattern.inhaleDurationMs / 1000,
    apexAtSeconds: cycleStartSeconds + pattern.inhaleDurationMs / 1000 + pattern.exhaleDurationMs / 2000,
    settleAtSeconds: cycleStartSeconds + pattern.cycleDurationMs / 1000,
  };
}

function sensitivityConfig(sensitivity) {
  switch (sensitivity) {
    case 'gentle':
      return { response: 12, damping: 8.4, accelerationScale: 0.8 };
    case 'responsive':
      return { response: 20, damping: 7, accelerationScale: 1.12 };
    default:
      return { response: 16, damping: 7.5, accelerationScale: 1 };
  }
}

export function createGameState(config = {}) {
  const mode = config.mode === 'endless' ? 'endless' : 'quick';
  const seed = String(config.seed ?? `${Date.now()}-${Math.random()}`);
  const random = createSeededRandom(seed);
  const breathingPattern = createBreathingPattern(config.breathingPace);
  const state = {
    mode,
    phase: 'opening',
    elapsed: 0,
    duration: mode === 'quick' ? FLOW_CONSTANTS.quickDuration : Number.POSITIVE_INFINITY,
    seed,
    random,
    viewport: { width: 0, height: 0, dpr: 1 },
    road: {
      samples: [],
      corners: [],
      travelled: 0,
      speed: FLOW_CONSTANTS.baseTravelSpeed,
      difficulty: 0,
      nextDistance: 0,
      nextCenterX: FLOW_CONSTANTS.worldWidth / 2,
      pendingRecovery: false,
      generatedSections: 0,
    },
    bike: {
      x: FLOW_CONSTANTS.worldWidth / 2,
      velocityX: 0,
      lean: 0,
      targetX: FLOW_CONSTANTS.worldWidth / 2,
    },
    input: {
      active: false,
      target: 0,
      previous: 0,
      delta: 0,
      previousDelta: 0,
      jerk: 0,
      rollingJerk: 0,
    },
    metrics: {
      score: 0,
      flow: FLOW_CONSTANTS.initialFlow,
      smoothness: 100,
      cleanApexes: 0,
      perfectApexes: 0,
      totalApexes: 0,
      currentStreak: 0,
      longestStreak: 0,
      timeInFlow: 0,
      lineQuality: 1,
      lastApex: null,
      scoredTime: 0,
      lineQualityIntegral: 0,
      smoothnessIntegral: 0,
    },
    breathing: {
      enabled: config.breathingGuide !== 'off',
      guide: ['guided', 'subtle', 'off'].includes(config.breathingGuide) ? config.breathingGuide : 'guided',
      pattern: breathingPattern,
      phase: 'inhale',
      phaseProgress: 0,
      cycleIndex: 0,
      visualEnvelope: 0,
    },
    processedCorners: new Set(),
    paused: false,
    completed: false,
    completionReason: null,
    settings: {
      inputSensitivity: ['gentle', 'balanced', 'responsive'].includes(config.inputSensitivity)
        ? config.inputSensitivity
        : 'balanced',
    },
  };

  if (mode === 'quick') {
    appendQuickResetCourse(state, random);
  } else {
    appendStraightSection(state, 360, true);
    while (state.road.nextDistance < FLOW_CONSTANTS.roadAheadDistance) {
      generateRoadSection(state, random);
    }
  }
  updateBreathingState(state);
  return state;
}

function appendSample(state, sample) {
  state.road.samples.push(sample);
  state.road.nextDistance = sample.distance + FLOW_CONSTANTS.roadSampleStep;
  state.road.nextCenterX = sample.centerX;
}

function appendStraightSection(state, length, opening = false) {
  const startDistance = state.road.nextDistance;
  const center = state.road.nextCenterX;
  const count = Math.max(2, Math.ceil(length / FLOW_CONSTANTS.roadSampleStep));
  for (let index = 0; index <= count; index += 1) {
    appendSample(state, {
      distance: startDistance + index * FLOW_CONSTANTS.roadSampleStep,
      centerX: center,
      width: FLOW_CONSTANTS.roadHalfWidth,
      curvature: 0,
      targetX: center,
      apexWeight: 0,
      cornerId: null,
      isRecovery: !opening,
    });
  }
  state.road.generatedSections += 1;
}

function appendBreathCorner(state, random, cycleDistance, intensityRange, breathCycle) {
  const pattern = state.breathing.pattern;
  const inhaleRatio = pattern.inhaleDurationMs / pattern.cycleDurationMs;
  const approachLength = cycleDistance * (inhaleRatio + 0.04);
  const cornerLength = cycleDistance * 0.44;
  const recoveryLength = Math.max(90, cycleDistance - approachLength - cornerLength);
  appendStraightSection(state, approachLength);

  const direction = random() < 0.5 ? -1 : 1;
  const intensity = randomBetween(random, intensityRange[0], intensityRange[1]);
  const startDistance = state.road.nextDistance;
  const startCenter = state.road.nextCenterX;
  const margin = FLOW_CONSTANTS.roadHalfWidth + 65;
  let centerOffset = direction * (185 + intensity * 75);
  if (startCenter + centerOffset < margin || startCenter + centerOffset > FLOW_CONSTANTS.worldWidth - margin) {
    centerOffset *= -1;
  }
  const effectiveDirection = Math.sign(centerOffset) || direction;
  const endCenter = clamp(startCenter + centerOffset, margin, FLOW_CONSTANTS.worldWidth - margin);
  const cornerId = `breath-corner-${breathCycle}`;
  const apexPhase = 0.5;
  const count = Math.max(8, Math.ceil(cornerLength / FLOW_CONSTANTS.roadSampleStep));
  const width = FLOW_CONSTANTS.roadHalfWidth - intensity * 10;

  for (let index = 0; index <= count; index += 1) {
    const phase = index / count;
    const centerX = startCenter + (endCenter - startCenter) * smoothstep(phase);
    const outside = -effectiveDirection * width * 0.3;
    const inside = effectiveDirection * width * 0.38;
    const lineOffset = phase < apexPhase
      ? outside + (inside - outside) * smoothstep(phase / apexPhase)
      : inside + (outside - inside) * smoothstep((phase - apexPhase) / (1 - apexPhase));
    appendSample(state, {
      distance: startDistance + index * FLOW_CONSTANTS.roadSampleStep,
      centerX,
      width,
      curvature: effectiveDirection * intensity * Math.sin(Math.PI * phase),
      targetX: centerX + lineOffset,
      apexWeight: Math.exp(-Math.pow((phase - apexPhase) / 0.12, 2)),
      cornerId,
      isRecovery: false,
    });
  }
  state.road.corners.push({
    id: cornerId,
    direction: effectiveDirection,
    intensity,
    breathCycle,
    startDistance,
    apexDistance: startDistance + cornerLength * apexPhase,
    endDistance: startDistance + cornerLength,
  });
  state.road.generatedSections += 1;
  appendStraightSection(state, recoveryLength);
}

function appendQuickResetCourse(state, random) {
  const speed = FLOW_CONSTANTS.baseTravelSpeed;
  appendStraightSection(state, FLOW_CONSTANTS.arriveDuration * speed, true);
  const pacedDuration = FLOW_CONSTANTS.followDuration + FLOW_CONSTANTS.flowDuration;
  const cycleSeconds = state.breathing.pattern.cycleDurationMs / 1000;
  let pacedElapsed = 0;
  let cycleIndex = 0;
  while (pacedElapsed < pacedDuration - 0.01) {
    const remaining = pacedDuration - pacedElapsed;
    const sectionSeconds = Math.min(cycleSeconds, remaining);
    const isFollow = pacedElapsed < FLOW_CONSTANTS.followDuration;
    appendBreathCorner(
      state,
      random,
      sectionSeconds * speed,
      isFollow ? [0.22, 0.38] : [0.34, 0.68],
      cycleIndex,
    );
    pacedElapsed += sectionSeconds;
    cycleIndex += 1;
  }
  appendStraightSection(state, FLOW_CONSTANTS.landDuration * speed);
  appendStraightSection(state, FLOW_CONSTANTS.roadAheadDistance + 300);
}

export function generateRoadSection(state, random = state.random) {
  if (state.road.pendingRecovery) {
    state.road.pendingRecovery = false;
    appendStraightSection(state, randomBetween(random, 150, 230));
    return state;
  }

  const difficulty = clamp(state.road.difficulty, 0, 1);
  const direction = random() < 0.5 ? -1 : 1;
  const intensity = randomBetween(random, 0.28, 0.72 + difficulty * 0.18);
  const length = randomBetween(random, 300 - difficulty * 30, 500 - difficulty * 70);
  const startDistance = state.road.nextDistance;
  const startCenter = state.road.nextCenterX;
  const maximumOffset = 210 + difficulty * 55;
  let centerOffset = direction * maximumOffset * intensity;
  const margin = FLOW_CONSTANTS.roadHalfWidth + 65;
  const proposedEnd = startCenter + centerOffset;
  if (proposedEnd < margin || proposedEnd > FLOW_CONSTANTS.worldWidth - margin) {
    centerOffset *= -1;
  }
  const effectiveDirection = Math.sign(centerOffset) || direction;
  const endCenter = clamp(
    startCenter + centerOffset,
    margin,
    FLOW_CONSTANTS.worldWidth - margin,
  );
  const cornerId = `corner-${state.road.generatedSections}`;
  const apexDistance = startDistance + length * 0.56;
  const count = Math.max(4, Math.ceil(length / FLOW_CONSTANTS.roadSampleStep));
  const width = clamp(
    FLOW_CONSTANTS.roadHalfWidth - difficulty * 28 - intensity * 12,
    FLOW_CONSTANTS.minimumRoadHalfWidth,
    FLOW_CONSTANTS.roadHalfWidth,
  );

  for (let index = 0; index <= count; index += 1) {
    const phase = index / count;
    const bend = smoothstep(phase);
    const centerX = startCenter + (endCenter - startCenter) * bend;
    // The abstract guide moves outside, through the apex, then settles outside.
    // It is intentionally a game path, not real-world road-riding instruction.
    const outside = -effectiveDirection * width * 0.34;
    const inside = effectiveDirection * width * 0.42;
    let lineOffset;
    if (phase < 0.56) {
      lineOffset = outside + (inside - outside) * smoothstep(phase / 0.56);
    } else {
      lineOffset = inside + (outside - inside) * smoothstep((phase - 0.56) / 0.44);
    }
    const apexWeight = Math.exp(-Math.pow((phase - 0.56) / 0.115, 2));
    appendSample(state, {
      distance: startDistance + index * FLOW_CONSTANTS.roadSampleStep,
      centerX,
      width,
      curvature: effectiveDirection * intensity * Math.sin(Math.PI * phase),
      targetX: centerX + lineOffset,
      apexWeight,
      cornerId,
      isRecovery: false,
    });
  }

  state.road.corners.push({
    id: cornerId,
    direction: effectiveDirection,
    intensity,
    startDistance,
    apexDistance,
    endDistance: startDistance + length,
  });
  state.road.pendingRecovery = intensity > 0.66;
  state.road.generatedSections += 1;
  return state;
}

export function ensureRoadAhead(state, random = state.random) {
  const requiredDistance = state.road.travelled + FLOW_CONSTANTS.roadAheadDistance;
  while (state.road.nextDistance < requiredDistance) {
    generateRoadSection(state, random);
  }
  // Keep enough history for a stable interpolation behind the rider while
  // bounding memory use during long Open Road sessions.
  const retainAfter = state.road.travelled - 160;
  let firstRetained = 0;
  while (
    firstRetained < state.road.samples.length - 2
    && state.road.samples[firstRetained + 1].distance < retainAfter
  ) {
    firstRetained += 1;
  }
  if (firstRetained > 0) state.road.samples.splice(0, firstRetained);
  state.road.corners = state.road.corners.filter(corner => corner.endDistance >= retainAfter);
}

export function sampleRoadAtDistance(state, distance) {
  const samples = state.road.samples;
  if (!samples.length) {
    return {
      distance,
      centerX: FLOW_CONSTANTS.worldWidth / 2,
      width: FLOW_CONSTANTS.roadHalfWidth,
      curvature: 0,
      targetX: FLOW_CONSTANTS.worldWidth / 2,
      apexWeight: 0,
      cornerId: null,
      isRecovery: false,
    };
  }
  if (distance <= samples[0].distance) return samples[0];
  if (distance >= samples[samples.length - 1].distance) return samples[samples.length - 1];

  let low = 0;
  let high = samples.length - 1;
  while (low + 1 < high) {
    const middle = Math.floor((low + high) / 2);
    if (samples[middle].distance <= distance) low = middle;
    else high = middle;
  }
  const before = samples[low];
  const after = samples[high];
  const span = Math.max(1, after.distance - before.distance);
  const ratio = clamp((distance - before.distance) / span, 0, 1);
  return {
    distance,
    centerX: before.centerX + (after.centerX - before.centerX) * ratio,
    width: before.width + (after.width - before.width) * ratio,
    curvature: before.curvature + (after.curvature - before.curvature) * ratio,
    targetX: before.targetX + (after.targetX - before.targetX) * ratio,
    apexWeight: Math.max(before.apexWeight, after.apexWeight),
    cornerId: ratio < 0.5 ? before.cornerId : after.cornerId,
    isRecovery: before.isRecovery || after.isRecovery,
  };
}

export function updateRoad(state, deltaTime) {
  const dt = clamp(deltaTime, 0, FLOW_CONSTANTS.maximumDeltaTime);
  const endlessProgress = state.mode === 'endless' ? clamp(state.elapsed / 300, 0, 1) : 0;
  state.road.difficulty = state.mode === 'quick'
    ? (state.phase === 'flow' ? 0.32 : 0.08)
    : endlessProgress;
  state.road.speed = FLOW_CONSTANTS.baseTravelSpeed * (1 + state.road.difficulty * 0.18);
  state.road.travelled += state.road.speed * dt;
  if (state.mode === 'endless') ensureRoadAhead(state);
  return state;
}

export function updateBike(state, inputTarget, deltaTime) {
  const dt = clamp(deltaTime, 0, FLOW_CONSTANTS.maximumDeltaTime);
  const road = sampleRoadAtDistance(state, state.road.travelled);
  const target = clamp(Number.isFinite(inputTarget) ? inputTarget : state.input.target, -1, 1);
  state.input.active = true;
  state.input.target = target;
  state.input.delta = target - state.input.previous;
  state.input.jerk = state.input.delta - state.input.previousDelta;
  state.input.rollingJerk = state.input.rollingJerk * 0.88 + Math.abs(state.input.jerk) * 0.12;
  state.input.previous = target;
  state.input.previousDelta = state.input.delta;

  const sensitivity = sensitivityConfig(state.settings.inputSensitivity);
  const desiredX = road.centerX + target * road.width * 0.92;
  state.bike.targetX = desiredX;
  const breathResponse = state.breathing?.enabled
    ? (state.breathing.phase === 'inhale' ? 0.96 : 1.03)
    : 1;
  const requestedAcceleration = (desiredX - state.bike.x) * sensitivity.response * breathResponse;
  const maximumAcceleration = FLOW_CONSTANTS.maximumLateralAcceleration * sensitivity.accelerationScale;
  const acceleration = clamp(requestedAcceleration, -maximumAcceleration, maximumAcceleration);
  state.bike.velocityX += acceleration * dt;
  state.bike.velocityX *= Math.exp(-sensitivity.damping * dt);
  state.bike.velocityX = clamp(
    state.bike.velocityX,
    -FLOW_CONSTANTS.maximumLateralVelocity,
    FLOW_CONSTANTS.maximumLateralVelocity,
  );
  state.bike.x += state.bike.velocityX * dt;
  state.bike.x = clamp(
    state.bike.x,
    road.centerX - road.width * 1.25,
    road.centerX + road.width * 1.25,
  );
  state.bike.lean += (clamp(state.bike.velocityX / 520, -1, 1) - state.bike.lean) * (1 - Math.exp(-8 * dt));
  return state;
}

export function calculateLineQuality(state) {
  const road = sampleRoadAtDistance(state, state.road.travelled);
  const lineError = Math.abs(state.bike.x - road.targetX);
  return clamp(1 - lineError / Math.max(1, road.width), 0, 1);
}

export function calculateSmoothness(state) {
  const velocityPenalty = Math.min(0.22, Math.abs(state.bike.velocityX) / 2800);
  const jerkPenalty = Math.min(0.8, state.input.rollingJerk * 2.8);
  return clamp((1 - velocityPenalty - jerkPenalty) * 100, 0, 100);
}

export function updateFlowMeter(state, metrics, deltaTime) {
  const dt = clamp(deltaTime, 0, FLOW_CONSTANTS.maximumDeltaTime);
  const quality = clamp(metrics.lineQuality, 0, 1);
  const smoothness = clamp(metrics.smoothness / 100, 0, 1);
  let rate = (quality - 0.58) * 13 + (smoothness - 0.72) * 4.5;
  const road = sampleRoadAtDistance(state, state.road.travelled);
  const outsideRoad = Math.abs(state.bike.x - road.centerX) > road.width;
  if (outsideRoad) rate -= 18;
  if (state.input.rollingJerk > 0.2) rate -= 4;
  state.metrics.flow = clamp(state.metrics.flow + rate * dt, 0, 100);
  if (state.mode === 'quick' && state.elapsed < FLOW_CONSTANTS.quickProtectionDuration) {
    state.metrics.flow = Math.max(10, state.metrics.flow);
  }
  if (state.metrics.flow >= FLOW_CONSTANTS.highFlowThreshold) {
    state.metrics.timeInFlow += dt;
  }
  return state.metrics.flow;
}

function gradeApex(normalisedError) {
  if (normalisedError <= 0.08) return { grade: 'perfect', label: 'Perfect line', score: 4 };
  if (normalisedError <= 0.15) return { grade: 'clean', label: 'Clean apex', score: 3 };
  if (normalisedError <= 0.25) return { grade: 'settled', label: 'Settled', score: 2 };
  return { grade: 'missed', label: 'Find the rhythm', score: 0 };
}

export function detectApexResult(state) {
  const corner = state.road.corners.find(candidate => (
    candidate.apexDistance <= state.road.travelled
    && !state.processedCorners.has(candidate.id)
  ));
  if (!corner) return null;
  state.processedCorners.add(corner.id);
  const road = sampleRoadAtDistance(state, corner.apexDistance);
  const normalisedError = Math.abs(state.bike.x - road.targetX) / Math.max(1, road.width);
  const result = { ...gradeApex(normalisedError), cornerId: corner.id, normalisedError };
  state.metrics.totalApexes += 1;
  if (result.grade === 'perfect') {
    state.metrics.perfectApexes += 1;
    state.metrics.cleanApexes += 1;
  } else if (result.grade === 'clean') {
    state.metrics.cleanApexes += 1;
  }
  if (result.score >= 2) {
    state.metrics.currentStreak += 1;
    state.metrics.longestStreak = Math.max(state.metrics.longestStreak, state.metrics.currentStreak);
    state.metrics.flow = clamp(state.metrics.flow + result.score * 1.2, 0, 100);
  } else {
    state.metrics.currentStreak = 0;
    state.metrics.flow = clamp(state.metrics.flow - 4, 0, 100);
  }
  state.metrics.lastApex = result;
  return result;
}

export function updateScore(state, metrics, deltaTime) {
  const dt = clamp(deltaTime, 0, FLOW_CONSTANTS.maximumDeltaTime);
  const lineComponent = clamp(metrics.lineQuality, 0, 1);
  const smoothComponent = clamp(metrics.smoothness / 100, 0, 1);
  const streakMultiplier = Math.min(3, 1 + state.metrics.currentStreak * 0.08);
  const techniqueQuality = lineComponent * 0.72 + smoothComponent * 0.28;
  state.metrics.score += techniqueQuality * dt * FLOW_CONSTANTS.scoreRate * streakMultiplier;
  state.metrics.scoredTime += dt;
  state.metrics.lineQualityIntegral += lineComponent * dt;
  state.metrics.smoothnessIntegral += smoothComponent * dt;
  return state.metrics.score;
}

function markUnscoredCornersProcessed(state) {
  for (const corner of state.road.corners) {
    if (corner.apexDistance <= state.road.travelled) state.processedCorners.add(corner.id);
  }
}

export function stepGame(state, inputTarget, deltaTime) {
  if (state.paused || state.completed) return { state, apex: null };
  const dt = clamp(deltaTime, 0, FLOW_CONSTANTS.maximumDeltaTime);
  if (dt <= 0) return { state, apex: null };
  state.elapsed += dt;
  state.phase = state.mode === 'quick' ? getQuickResetStage(state.elapsed) : 'open-road';
  updateBreathingState(state);
  updateRoad(state, dt);
  updateBike(state, inputTarget, dt);
  const lineQuality = calculateLineQuality(state);
  const smoothness = calculateSmoothness(state);
  state.metrics.lineQuality = lineQuality;
  state.metrics.smoothness += (smoothness - state.metrics.smoothness) * (1 - Math.exp(-4 * dt));
  const scoringActive = state.mode === 'endless' || state.phase === 'flow';
  let apex = null;
  if (scoringActive) {
    updateFlowMeter(state, { lineQuality, smoothness: state.metrics.smoothness }, dt);
    updateScore(state, { lineQuality, smoothness: state.metrics.smoothness }, dt);
    apex = detectApexResult(state);
  } else {
    markUnscoredCornersProcessed(state);
  }

  if (state.mode === 'quick' && state.elapsed >= state.duration) {
    finishSession(state, 'complete');
  } else if (state.mode === 'endless' && state.metrics.flow <= 0) {
    finishSession(state, 'flow-ended');
  }
  return { state, apex };
}

export function finishSession(state, reason = 'complete') {
  state.completed = true;
  state.paused = false;
  state.phase = 'complete';
  state.completionReason = reason;
  const apexRate = state.metrics.totalApexes
    ? state.metrics.cleanApexes / state.metrics.totalApexes
    : 0;
  const averageLineQuality = state.metrics.scoredTime > 0
    ? state.metrics.lineQualityIntegral / state.metrics.scoredTime
    : state.metrics.lineQuality;
  const averageSmoothness = state.metrics.scoredTime > 0
    ? state.metrics.smoothnessIntegral / state.metrics.scoredTime
    : state.metrics.smoothness / 100;
  const techniqueScore = clamp(
    averageLineQuality * 54
      + averageSmoothness * 31
      + apexRate * 15,
    0,
    100,
  );
  return {
    mode: state.mode,
    seed: state.seed,
    score: Math.round(state.metrics.score),
    flowScore: Math.round(techniqueScore),
    durationSeconds: Math.round(state.elapsed),
    smoothness: Math.round(state.metrics.smoothness),
    cleanApexRate: Math.round(apexRate * 100),
    perfectApexes: state.metrics.perfectApexes,
    corners: state.metrics.totalApexes,
    longestStreak: state.metrics.longestStreak,
    timeInFlow: Math.round(state.metrics.timeInFlow),
    reason,
  };
}

export function resizeViewport(state, width, height, dpr = 1) {
  state.viewport.width = Math.max(1, Number(width) || 1);
  state.viewport.height = Math.max(1, Number(height) || 1);
  state.viewport.dpr = clamp(Number(dpr) || 1, 1, 2);
  return state.viewport;
}
