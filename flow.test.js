import test from 'node:test';
import assert from 'node:assert/strict';
import {
  FLOW_CONSTANTS,
  calculateLineQuality,
  createBreathingPattern,
  createGameState,
  createSeededRandom,
  finishSession,
  generateRoadSection,
  getBreathingPhaseAtTime,
  getBreathingVisualEnvelope,
  getQuickResetStage,
  sampleRoadAtDistance,
  stepGame,
  updateBike,
} from './flow-engine.js';
import {
  FLOW_SESSION_LIMIT,
  FLOW_STORAGE_KEY,
  loadFlowData,
  recordFlowSession,
} from './flow-storage.js';
import {
  MOTORCYCLE_PRESETS,
  PARTICLE_PRESETS,
  QUALITY_PRESETS,
  SKY_PRESETS,
} from './flow-assets.js';
import {
  ParticlePool,
  createMountainLayers,
  createVisualRandom,
} from './flow-effects.js';

function roadSignature(seed) {
  const state = createGameState({ seed });
  return state.road.samples.slice(130, 260).map(sample => [
    Math.round(sample.centerX * 100) / 100,
    Math.round(sample.targetX * 100) / 100,
    sample.cornerId,
  ]);
}

test('same seed produces the same road and different seeds diverge', () => {
  assert.deepEqual(roadSignature('quiet-road'), roadSignature('quiet-road'));
  assert.notDeepEqual(roadSignature('quiet-road'), roadSignature('open-road'));
});

test('visual asset presets expose the complete scalable library', () => {
  assert.equal(Object.keys(SKY_PRESETS).length, 7);
  assert.equal(Object.keys(MOTORCYCLE_PRESETS).length, 6);
  assert.ok(Object.keys(PARTICLE_PRESETS).length >= 7);
  assert.deepEqual(Object.keys(QUALITY_PRESETS), ['low', 'balanced', 'high']);
});

test('procedural visual layers are seeded and particle counts remain bounded', () => {
  assert.deepEqual(createMountainLayers('night-run'), createMountainLayers('night-run'));
  assert.notDeepEqual(createMountainLayers('night-run'), createMountainLayers('blue-run'));
  const randomA = createVisualRandom('visual');
  const randomB = createVisualRandom('visual');
  assert.deepEqual([randomA(), randomA(), randomA()], [randomB(), randomB(), randomB()]);

  const pool = new ParticlePool('pool', 12);
  pool.configure({ count: 80, type: 'rain', width: 390, height: 844 });
  pool.update(1, 0.6);
  let count = 0;
  pool.forEach(particle => {
    count += 1;
    assert.ok(Number.isFinite(particle.x));
    assert.ok(Number.isFinite(particle.y));
  });
  assert.equal(count, 12);
});

test('generated road stays valid and difficult corners receive recovery space', () => {
  const state = createGameState({ seed: 'bounds' });
  const random = createSeededRandom('more-road');
  for (let index = 0; index < 40; index += 1) generateRoadSection(state, random);
  for (const sample of state.road.samples) {
    assert.ok(Number.isFinite(sample.centerX));
    assert.ok(sample.centerX - sample.width >= 0);
    assert.ok(sample.centerX + sample.width <= FLOW_CONSTANTS.worldWidth);
    assert.ok(sample.width >= FLOW_CONSTANTS.minimumRoadHalfWidth);
  }
  const difficultCorners = state.road.corners.filter(corner => corner.intensity > 0.66);
  assert.ok(difficultCorners.length > 0);
  for (const corner of difficultCorners) {
    const recovery = state.road.samples.find(sample => (
      sample.distance > corner.endDistance && sample.isRecovery
    ));
    assert.ok(recovery, `missing recovery after ${corner.id}`);
  }
});

test('bike moves toward intention with bounded finite motion', () => {
  const state = createGameState({ seed: 'bike' });
  const initialX = state.bike.x;
  for (let index = 0; index < 90; index += 1) updateBike(state, 0.8, 1 / 60);
  assert.ok(state.bike.x > initialX);
  assert.ok(Math.abs(state.bike.velocityX) <= FLOW_CONSTANTS.maximumLateralVelocity);
  assert.ok(Number.isFinite(state.bike.x));
  assert.ok(Number.isFinite(state.bike.lean));
});

test('line quality rewards proximity to the abstract guide', () => {
  const state = createGameState({ seed: 'line' });
  const road = sampleRoadAtDistance(state, state.road.travelled);
  state.bike.x = road.targetX;
  const perfect = calculateLineQuality(state);
  state.bike.x = road.targetX + road.width;
  const poor = calculateLineQuality(state);
  assert.ok(perfect > 0.99);
  assert.ok(poor < 0.01);
});

test('smooth input produces a better session than repeated sharp corrections', () => {
  const calm = createGameState({ seed: 'comparison', mode: 'endless' });
  const abrupt = createGameState({ seed: 'comparison', mode: 'endless' });
  for (let index = 0; index < 1200; index += 1) {
    const gentleInput = Math.sin(index / 180) * 0.35;
    const abruptInput = index % 8 < 4 ? -0.9 : 0.9;
    stepGame(calm, gentleInput, 1 / 60);
    stepGame(abrupt, abruptInput, 1 / 60);
  }
  assert.ok(calm.metrics.smoothness > abrupt.metrics.smoothness);
  assert.ok(calm.metrics.flow > abrupt.metrics.flow);
});

test('breathing presets expose deterministic phases and smooth visual envelopes', () => {
  const settle = createBreathingPattern('settle');
  assert.equal(settle.inhaleDurationMs, 4000);
  assert.equal(settle.exhaleDurationMs, 6000);
  assert.deepEqual(getBreathingPhaseAtTime(settle, 2000), {
    phase: 'inhale', phaseProgress: 0.5, cycleIndex: 0,
  });
  assert.deepEqual(getBreathingPhaseAtTime(settle, 7000), {
    phase: 'exhale', phaseProgress: 0.5, cycleIndex: 0,
  });
  assert.ok(getBreathingVisualEnvelope({ phase: 'inhale', phaseProgress: 0.75 }) > 0.5);
  assert.ok(getBreathingVisualEnvelope({ phase: 'exhale', phaseProgress: 0.75 }) < 0.5);
});

test('Quick Reset follows arrive, follow, flow, and land stages', () => {
  assert.equal(getQuickResetStage(0), 'arrive');
  assert.equal(getQuickResetStage(14.99), 'arrive');
  assert.equal(getQuickResetStage(15), 'follow');
  assert.equal(getQuickResetStage(35), 'flow');
  assert.equal(getQuickResetStage(75), 'land');
  assert.equal(getQuickResetStage(90), 'complete');
});

test('Quick Reset does not score during arrive or follow', () => {
  const state = createGameState({ seed: 'staged-reset', mode: 'quick' });
  for (let index = 0; index < 34 * 60; index += 1) stepGame(state, 0, 1 / 60);
  assert.equal(state.metrics.score, 0);
  assert.equal(state.metrics.totalApexes, 0);
  assert.equal(state.phase, 'follow');
  for (let index = 0; index < 3 * 60; index += 1) stepGame(state, 0, 1 / 60);
  assert.ok(state.metrics.score > 0);
  assert.equal(state.phase, 'flow');
});

test('flow stays bounded and Quick Reset completes at ninety seconds', () => {
  const state = createGameState({ seed: 'quick', mode: 'quick' });
  for (let index = 0; index < 6000 && !state.completed; index += 1) {
    stepGame(state, 0, 1 / 60);
    assert.ok(state.metrics.flow >= 0 && state.metrics.flow <= 100);
  }
  assert.equal(state.completed, true);
  assert.ok(state.elapsed >= 90 && state.elapsed < 90.1);
});

test('paused time does not advance and large frame delays are clamped', () => {
  const state = createGameState({ seed: 'pause' });
  state.paused = true;
  stepGame(state, 0, 10);
  assert.equal(state.elapsed, 0);
  state.paused = false;
  stepGame(state, 0, 10);
  assert.equal(state.elapsed, FLOW_CONSTANTS.maximumDeltaTime);
});

test('deterministic input produces deterministic session results', () => {
  const run = () => {
    const state = createGameState({ seed: 'repeatable' });
    for (let index = 0; index < 1800; index += 1) {
      stepGame(state, Math.sin(index / 120) * 0.5, 1 / 60);
    }
    return finishSession(state, 'test');
  };
  assert.deepEqual(run(), run());
});

test('invalid persisted data fails safely', () => {
  const storage = {
    getItem: () => '{broken',
    setItem: () => {},
  };
  const data = loadFlowData(storage);
  assert.equal(data.settings.inputSensitivity, 'balanced');
  assert.equal(data.settings.quality, 'balanced');
  assert.equal(data.settings.motorcycle, 'sport');
  assert.deepEqual(data.sessions, []);
});

test('session history is capped and bests are retained', () => {
  const memory = new Map();
  const storage = {
    getItem: key => memory.get(key) ?? null,
    setItem: (key, value) => memory.set(key, value),
  };
  let data = loadFlowData(storage);
  for (let index = 0; index < FLOW_SESSION_LIMIT + 7; index += 1) {
    data = recordFlowSession(data, {
      mode: 'quick', score: index, flowScore: index, smoothness: index,
      cleanApexRate: index, longestStreak: index,
    }, storage);
  }
  assert.equal(data.sessions.length, FLOW_SESSION_LIMIT);
  assert.equal(data.bests.quick.score, FLOW_SESSION_LIMIT + 6);
  assert.ok(memory.has(FLOW_STORAGE_KEY));
});
