const FLOW_CONFIG = Object.freeze({
  storageKey: 'memoryLanes.flow.ritual.v1',
  sessionDefaultMs: 300000,
  extensionMs: 300000,
  historyLimit: 20,
  coherent: Object.freeze({
    cycleStartMs: 8000,
    cycleTargetMs: 10000,
    rampMs: 45000,
    inhaleRatio: 0.4,
    exhaleRatio: 0.6,
    minTargetMs: 8000,
    maxTargetMs: 12000,
    stepMs: 500
  }),
  sighing: Object.freeze({
    inhale1Ms: 1500,
    inhale2Ms: 1000,
    exhaleMs: 5000,
    restMs: 500
  }),
  render: Object.freeze({
    dprCap: 2,
    particleCap: 26,
    maxDeltaMs: 80
  })
});

const root = document.getElementById('flow-root');
const canvas = document.getElementById('flow-canvas');
let context = canvas?.getContext('2d', { alpha: false }) || null;
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const rideId = new URLSearchParams(window.location.search).get('ride');

const elements = {
  checkIn: document.getElementById('flow-check-in'),
  ritual: document.getElementById('flow-ritual'),
  checkOut: document.getElementById('flow-check-out'),
  complete: document.getElementById('flow-complete'),
  close: document.getElementById('flow-close'),
  controlsToggle: document.getElementById('flow-controls-toggle'),
  controls: document.getElementById('flow-controls'),
  controlsDismiss: document.getElementById('flow-controls-dismiss'),
  pause: document.getElementById('flow-pause'),
  pausePanel: document.getElementById('flow-pause-panel'),
  resume: document.getElementById('flow-resume'),
  pauseEnd: document.getElementById('flow-pause-end'),
  endEarly: document.getElementById('flow-end-early'),
  extend: document.getElementById('flow-extend'),
  sound: document.getElementById('flow-sound'),
  paceControl: document.getElementById('flow-pace-control'),
  paceFaster: document.getElementById('flow-pace-faster'),
  paceSlower: document.getElementById('flow-pace-slower'),
  paceDescription: document.getElementById('flow-pace-description'),
  phaseKicker: document.getElementById('flow-phase-kicker'),
  phaseText: document.getElementById('flow-phase-text'),
  phaseDetail: document.getElementById('flow-phase-detail'),
  timeRemaining: document.getElementById('flow-time-remaining'),
  settleLabel: document.getElementById('flow-settle-label'),
  reducedPacer: document.querySelector('#flow-reduced-pacer span'),
  comparison: document.getElementById('flow-comparison'),
  journalRide: document.getElementById('flow-journal-ride'),
  done: document.getElementById('flow-done'),
  liveStatus: document.getElementById('flow-live-status')
};

const stored = readStorage();
const state = {
  view: 'check-in',
  pre: null,
  post: null,
  mode: stored.settings.mode,
  targetCycleMs: stored.settings.targetCycleMs,
  totalMs: FLOW_CONFIG.sessionDefaultMs,
  elapsedMs: 0,
  breathClockMs: 0,
  cycleIndex: 0,
  phase: 'inhale',
  phaseProgress: 0,
  envelope: 0,
  paused: false,
  hidden: false,
  soundEnabled: false,
  lastFrameAt: 0,
  rafId: 0,
  controlsTimer: 0,
  disposed: false,
  width: 0,
  height: 0,
  dpr: 1,
  particles: [],
  visualTime: 0,
  sessionStartedAt: null
};

state.palette = null;

const listeners = [];
let audio = null;

function clamp(value, minimum, maximum) {
  return Math.min(maximum, Math.max(minimum, value));
}

function lerp(start, end, amount) {
  return start + (end - start) * amount;
}

function easeOutCubic(value) {
  return 1 - Math.pow(1 - value, 3);
}

function easeInOutSine(value) {
  return -(Math.cos(Math.PI * value) - 1) / 2;
}

function easeInOutCubic(value) {
  return value < 0.5
    ? 4 * value * value * value
    : 1 - Math.pow(-2 * value + 2, 3) / 2;
}

function readStorage() {
  const fallback = {
    version: 1,
    settings: { mode: 'coherent', targetCycleMs: FLOW_CONFIG.coherent.cycleTargetMs },
    pending: null,
    sessions: []
  };
  try {
    const parsed = JSON.parse(localStorage.getItem(FLOW_CONFIG.storageKey) || 'null');
    if (!parsed || typeof parsed !== 'object') return fallback;
    const target = clamp(
      Number(parsed.settings?.targetCycleMs) || FLOW_CONFIG.coherent.cycleTargetMs,
      FLOW_CONFIG.coherent.minTargetMs,
      FLOW_CONFIG.coherent.maxTargetMs
    );
    return {
      version: 1,
      settings: {
        mode: parsed.settings?.mode === 'sighing' ? 'sighing' : 'coherent',
        targetCycleMs: target
      },
      pending: parsed.pending && typeof parsed.pending === 'object' ? parsed.pending : null,
      sessions: Array.isArray(parsed.sessions) ? parsed.sessions.slice(-FLOW_CONFIG.historyLimit) : []
    };
  } catch (error) {
    return fallback;
  }
}

function writeStorage(next) {
  try {
    localStorage.setItem(FLOW_CONFIG.storageKey, JSON.stringify(next));
  } catch (error) {
    elements.liveStatus.textContent = 'Flow could not save this check-in on this device.';
  }
}

function persistSettings() {
  stored.settings.mode = state.mode;
  stored.settings.targetCycleMs = state.targetCycleMs;
  writeStorage(stored);
}

function persistPreReport(value) {
  stored.pending = {
    rideId: rideId || null,
    pre: value,
    startedAt: new Date().toISOString()
  };
  writeStorage(stored);
}

function persistCompletedSession() {
  stored.sessions.push({
    rideId: rideId || null,
    pre: state.pre,
    post: state.post,
    timestamp: new Date().toISOString(),
    durationMs: Math.round(state.elapsedMs),
    mode: state.mode,
    targetCycleMs: state.targetCycleMs
  });
  stored.sessions = stored.sessions.slice(-FLOW_CONFIG.historyLimit);
  stored.pending = null;
  persistSettings();
}

function on(target, type, handler, options) {
  target?.addEventListener(type, handler, options);
  listeners.push(() => target?.removeEventListener(type, handler, options));
}

function setView(view) {
  state.view = view;
  root.dataset.view = view;
  elements.checkIn.hidden = view !== 'check-in';
  elements.ritual.hidden = view !== 'ritual';
  elements.checkOut.hidden = view !== 'check-out';
  elements.complete.hidden = view !== 'complete';
  elements.controlsToggle.hidden = view !== 'ritual';
  if (view !== 'ritual') hideControls();
}

function resizeCanvas() {
  if (!canvas || !context) return;
  const rect = canvas.getBoundingClientRect();
  state.width = Math.max(1, rect.width);
  state.height = Math.max(1, rect.height);
  state.dpr = Math.min(window.devicePixelRatio || 1, FLOW_CONFIG.render.dprCap);
  canvas.width = Math.round(state.width * state.dpr);
  canvas.height = Math.round(state.height * state.dpr);
  context.setTransform(state.dpr, 0, 0, state.dpr, 0, 0);
  state.palette = resolvePalette();
  seedParticles();
  render();
}

function seedParticles() {
  state.particles.length = 0;
  if (reducedMotion) return;
  const count = Math.min(FLOW_CONFIG.render.particleCap, Math.round(state.width / 12));
  for (let index = 0; index < count; index += 1) {
    state.particles.push({
      x: Math.random() * state.width,
      y: Math.random() * state.height,
      size: 0.5 + Math.random() * 1.4,
      speed: 3 + Math.random() * 9,
      drift: Math.random() * 2 - 1,
      alpha: 0.12 + Math.random() * 0.3
    });
  }
}

function currentCycleDuration() {
  if (state.mode === 'sighing') {
    const pattern = FLOW_CONFIG.sighing;
    return pattern.inhale1Ms + pattern.inhale2Ms + pattern.exhaleMs + pattern.restMs;
  }
  const ramp = easeInOutCubic(clamp(state.elapsedMs / FLOW_CONFIG.coherent.rampMs, 0, 1));
  return lerp(FLOW_CONFIG.coherent.cycleStartMs, state.targetCycleMs, ramp);
}

function updateBreathing(deltaMs) {
  const cycleDuration = currentCycleDuration();
  state.breathClockMs += deltaMs;
  while (state.breathClockMs >= cycleDuration) {
    state.breathClockMs -= cycleDuration;
    state.cycleIndex += 1;
  }

  if (state.mode === 'coherent') {
    const inhaleMs = cycleDuration * FLOW_CONFIG.coherent.inhaleRatio;
    if (state.breathClockMs < inhaleMs) {
      state.phase = 'inhale';
      state.phaseProgress = state.breathClockMs / inhaleMs;
      state.envelope = easeOutCubic(state.phaseProgress);
    } else {
      state.phase = 'exhale';
      state.phaseProgress = (state.breathClockMs - inhaleMs) / (cycleDuration - inhaleMs);
      state.envelope = 1 - easeInOutSine(state.phaseProgress);
    }
    root.style.setProperty('--flow-phase-progress', `${state.phaseProgress * 100}%`);
    root.dataset.breathPhase = state.phase;
    return;
  }

  const pattern = FLOW_CONFIG.sighing;
  const clock = state.breathClockMs;
  if (clock < pattern.inhale1Ms) {
    state.phase = 'inhale1';
    state.phaseProgress = clock / pattern.inhale1Ms;
    state.envelope = easeOutCubic(state.phaseProgress) * 0.72;
  } else if (clock < pattern.inhale1Ms + pattern.inhale2Ms) {
    state.phase = 'inhale2';
    state.phaseProgress = (clock - pattern.inhale1Ms) / pattern.inhale2Ms;
    state.envelope = lerp(0.72, 1, easeOutCubic(state.phaseProgress));
  } else if (clock < pattern.inhale1Ms + pattern.inhale2Ms + pattern.exhaleMs) {
    state.phase = 'exhale';
    state.phaseProgress = (clock - pattern.inhale1Ms - pattern.inhale2Ms) / pattern.exhaleMs;
    state.envelope = 1 - easeInOutSine(state.phaseProgress);
  } else {
    state.phase = 'rest';
    state.phaseProgress = (clock - pattern.inhale1Ms - pattern.inhale2Ms - pattern.exhaleMs) / pattern.restMs;
    state.envelope = 0;
  }
  root.style.setProperty('--flow-phase-progress', `${state.phaseProgress * 100}%`);
  root.dataset.breathPhase = state.phase;
}

function updateTrail(deltaMs) {
  void deltaMs;
}

function updateParticles(deltaMs) {
  if (reducedMotion) return;
  const progress = clamp(state.elapsedMs / state.totalMs, 0, 1);
  const settling = 1 - 0.72 * easeInOutSine(progress);
  const outward = state.phase.startsWith('inhale') ? state.envelope : 0.08;
  for (const particle of state.particles) {
    const side = particle.x < state.width / 2 ? -1 : 1;
    particle.x += side * particle.drift * outward * deltaMs * 0.006;
    particle.y += particle.speed * settling * deltaMs * 0.004;
    if (particle.y > state.height + 10) {
      particle.y = -10;
      particle.x = Math.random() * state.width;
    }
  }
}

function frame(timestamp) {
  if (state.disposed || state.hidden || !context) return;
  if (!state.lastFrameAt) state.lastFrameAt = timestamp;
  const deltaMs = clamp(timestamp - state.lastFrameAt, 0, FLOW_CONFIG.render.maxDeltaMs);
  state.lastFrameAt = timestamp;

  if (!state.paused && state.view === 'ritual') {
    state.elapsedMs += deltaMs;
    state.visualTime += deltaMs;
    updateBreathing(deltaMs);
    updateTrail(deltaMs);
    updateParticles(deltaMs);
    updateRitualUI();
    updateAudio();
    if (state.elapsedMs >= state.totalMs) finishRitual();
  } else if (state.view !== 'ritual') {
    state.visualTime += deltaMs * 0.3;
    updateBreathing(deltaMs * 0.22);
    updateParticles(deltaMs * 0.3);
  }

  render();
  state.rafId = requestAnimationFrame(frame);
}

function render() {
  if (!context || !state.width || !state.height) return;
  const ctx = context;
  const width = state.width;
  const height = state.height;
  const ritualProgress = state.view === 'ritual' ? clamp(state.elapsedMs / state.totalMs, 0, 1) : 0.18;
  const finalMinute = state.totalMs - state.elapsedMs <= 60000 ? clamp((60000 - (state.totalMs - state.elapsedMs)) / 60000, 0, 1) : 0;
  const stillness = 1 - 0.72 * easeInOutSine(ritualProgress) - 0.16 * finalMinute;
  const drift = reducedMotion ? 0 : Math.sin(state.visualTime * 0.00011) * width * 0.008 * Math.max(0.08, stillness);
  const { background, depth, light, cyan, violet, warm } = state.palette || resolvePalette();
  const completionWarmth = state.view === 'complete' ? 0.16 : state.view === 'check-out' ? 0.07 : 0;

  ctx.setTransform(state.dpr, 0, 0, state.dpr, 0, 0);
  const field = ctx.createRadialGradient(width * 0.5, height * 0.46, 0, width * 0.5, height * 0.46, Math.max(width, height) * 0.74);
  field.addColorStop(0, colorWithAlpha(completionWarmth ? warm : depth, completionWarmth ? 0.08 : 0.94));
  if (completionWarmth) field.addColorStop(0.22, colorWithAlpha(depth, 0.92));
  field.addColorStop(0.52, background);
  field.addColorStop(1, colorWithAlpha(background, 0.98));
  ctx.fillStyle = field;
  ctx.fillRect(0, 0, width, height);

  drawAmbientField(ctx, width, height, drift, stillness, light, cyan, warm);
  drawInstrument(ctx, width, height, light, cyan, violet, warm, ritualProgress, stillness);
  drawSignalTrace(ctx, width, height, light, cyan, ritualProgress);
  drawParticles(ctx, light, cyan, ritualProgress, stillness);

  if (reducedMotion && elements.reducedPacer) {
    const scale = state.phase.startsWith('inhale') ? lerp(0.72, 1, state.envelope) : lerp(0.72, 1, state.envelope);
    elements.reducedPacer.style.transform = `scale(${scale})`;
    elements.reducedPacer.style.opacity = String(0.45 + state.envelope * 0.5);
  }
}

function drawAmbientField(ctx, width, height, drift, stillness, light, cyan, warm) {
  const centerX = width * 0.5 + drift;
  const centerY = height * 0.48;
  const pulse = easeInOutSine(state.envelope);
  const radius = Math.min(width, height) * (0.34 + pulse * 0.07);
  const glow = ctx.createRadialGradient(centerX, centerY, radius * 0.12, centerX, centerY, radius * 1.55);
  glow.addColorStop(0, colorWithAlpha(light, 0.1 + pulse * 0.08));
  glow.addColorStop(0.44, colorWithAlpha(cyan, 0.035 + pulse * 0.025));
  glow.addColorStop(0.82, colorWithAlpha(warm, 0.012));
  glow.addColorStop(1, colorWithAlpha(light, 0));
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, width, height);

  ctx.save();
  ctx.translate(centerX, centerY);
  ctx.rotate(-0.025 * stillness);
  for (let index = 0; index < 3; index += 1) {
    const orbitRadius = radius * (0.92 + index * 0.33 + pulse * 0.025);
    ctx.beginPath();
    ctx.ellipse(0, 0, orbitRadius, orbitRadius * (0.52 + index * 0.03), 0, Math.PI * 1.08, Math.PI * 1.92);
    ctx.strokeStyle = colorWithAlpha(index === 2 ? warm : light, 0.028 + index * 0.008);
    ctx.lineWidth = 1;
    ctx.stroke();
  }
  ctx.restore();
}

function drawInstrument(ctx, width, height, light, cyan, violet, warm, progress, stillness) {
  const x = width * 0.5;
  const y = height * (state.view === 'ritual' ? 0.49 : state.view === 'complete' ? 0.34 : 0.36);
  const pulse = easeInOutSine(state.envelope);
  const base = Math.min(width, height) * (state.view === 'ritual' ? 0.19 : 0.165);
  const breathingScale = reducedMotion ? 1 : lerp(0.92, 1.065, pulse);
  const radius = base * breathingScale;

  const bloom = ctx.createRadialGradient(x, y, radius * 0.14, x, y, radius * 1.72);
  const instrumentAccent = state.view === 'complete' ? warm : light;
  bloom.addColorStop(0, colorWithAlpha(instrumentAccent, 0.18 + pulse * 0.1));
  bloom.addColorStop(0.32, colorWithAlpha(cyan, 0.055 + pulse * 0.035));
  bloom.addColorStop(0.72, colorWithAlpha(violet, 0.012));
  bloom.addColorStop(1, colorWithAlpha(light, 0));
  ctx.fillStyle = bloom;
  ctx.fillRect(x - radius * 2, y - radius * 2, radius * 4, radius * 4);

  ctx.save();
  ctx.translate(x, y);
  ctx.lineCap = 'round';

  for (let ring = 0; ring < 2; ring += 1) {
    ctx.beginPath();
    ctx.arc(0, 0, radius * (0.68 + ring * 0.28), 0, Math.PI * 2);
    ctx.strokeStyle = colorWithAlpha(ring === 1 ? instrumentAccent : light, 0.065 - ring * 0.018);
    ctx.lineWidth = ring === 1 ? 1.1 : 0.8;
    ctx.stroke();
  }

  const dialRadius = radius * 1.04;
  for (let index = 0; index < 24; index += 1) {
    const angle = -Math.PI / 2 + index * Math.PI * 2 / 24;
    const major = index % 3 === 0;
    const active = index / 24 <= state.phaseProgress;
    const inner = dialRadius - (major ? radius * 0.075 : radius * 0.028);
    ctx.beginPath();
    ctx.moveTo(Math.cos(angle) * inner, Math.sin(angle) * inner);
    ctx.lineTo(Math.cos(angle) * dialRadius, Math.sin(angle) * dialRadius);
    ctx.strokeStyle = colorWithAlpha(active ? instrumentAccent : cyan, active ? 0.42 : major ? 0.12 : 0.045);
    ctx.lineWidth = major ? 1.35 : 0.7;
    ctx.stroke();
  }

  const phaseStart = -Math.PI / 2;
  const phaseSweep = Math.PI * 2 * state.phaseProgress;
  ctx.beginPath();
  ctx.arc(0, 0, dialRadius * 0.9, phaseStart, phaseStart + phaseSweep);
  ctx.strokeStyle = colorWithAlpha(state.phase.startsWith('inhale') ? light : instrumentAccent, 0.82);
  ctx.lineWidth = Math.max(2, radius * 0.025);
  ctx.shadowColor = state.phase.startsWith('inhale') ? light : instrumentAccent;
  ctx.shadowBlur = reducedMotion ? 0 : 8 + pulse * 7;
  ctx.stroke();

  const glass = ctx.createRadialGradient(0, -radius * 0.2, radius * 0.05, 0, 0, radius * 0.7);
  glass.addColorStop(0, colorWithAlpha(cyan, 0.08 + pulse * 0.04));
  glass.addColorStop(0.65, colorWithAlpha(light, 0.018));
  glass.addColorStop(1, colorWithAlpha(light, 0));
  ctx.fillStyle = glass;
  ctx.beginPath();
  ctx.arc(0, 0, radius * 0.66, 0, Math.PI * 2);
  ctx.fill();

  drawMemoryLanesMark(ctx, radius, light, cyan, pulse, progress, stillness);
  ctx.restore();
}

function drawMemoryLanesMark(ctx, radius, light, cyan, pulse, progress, stillness) {
  const size = radius * (0.39 + pulse * 0.025);
  ctx.save();
  ctx.shadowColor = light;
  ctx.shadowBlur = reducedMotion ? 0 : 13 + pulse * 18;
  ctx.strokeStyle = light;
  ctx.fillStyle = colorWithAlpha(cyan, 0.07 + pulse * 0.09);
  ctx.lineWidth = 2.2;
  ctx.beginPath();
  ctx.moveTo(-size, size * 0.52);
  ctx.bezierCurveTo(-size * 0.7, -size * 0.64, -size * 0.32, -size * 0.78, 0, -size * 0.12);
  ctx.bezierCurveTo(size * 0.35, size * 0.58, size * 0.68, size * 0.4, size, -size * 0.5);
  ctx.bezierCurveTo(size * 0.62, size * 0.74, size * 0.18, size * 0.78, -size * 0.12, size * 0.18);
  ctx.bezierCurveTo(-size * 0.44, -size * 0.45, -size * 0.68, -size * 0.27, -size, size * 0.52);
  ctx.fill();
  ctx.stroke();

  if (!reducedMotion) {
    const quiet = Math.max(0.14, stillness);
    for (let index = 0; index < 3; index += 1) {
      const release = (state.phaseProgress + index * 0.18) % 1;
      const ripple = radius * (0.43 + release * 0.48);
      ctx.beginPath();
      ctx.arc(0, 0, ripple, Math.PI * 0.15, Math.PI * 0.85);
      ctx.strokeStyle = colorWithAlpha(light, (0.1 - index * 0.018) * (1 - release) * quiet * (1 - progress * 0.42));
      ctx.lineWidth = 1;
      ctx.stroke();
    }
  }
  ctx.restore();
}

function drawSignalTrace(ctx, width, height, light, cyan, progress) {
  if (state.view !== 'ritual') return;
  const y = height * 0.705;
  const startX = width * 0.31;
  const length = width * 0.38;
  ctx.strokeStyle = colorWithAlpha(cyan, 0.12);
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(startX, y);
  ctx.lineTo(startX + length, y);
  ctx.stroke();

  const pointX = startX + length * state.phaseProgress;
  ctx.fillStyle = colorWithAlpha(light, 0.72);
  ctx.shadowColor = light;
  ctx.shadowBlur = reducedMotion ? 0 : 9;
  ctx.beginPath();
  ctx.arc(pointX, y, 2.6, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
}

function drawParticles(ctx, light, cyan, progress, stillness) {
  if (reducedMotion) return;
  const visibleFraction = (1 - 0.82 * easeInOutSine(progress)) * Math.max(0.12, stillness);
  const visibleCount = Math.max(6, Math.round(state.particles.length * visibleFraction));
  for (let index = 0; index < visibleCount; index += 1) {
    const particle = state.particles[index];
    ctx.fillStyle = colorWithAlpha(index % 3 === 0 ? cyan : light, particle.alpha * (0.28 + state.envelope * 0.34));
    ctx.fillRect(particle.x, particle.y, particle.size * 0.65, particle.size * 1.8);
  }
}

function colorWithAlpha(color, alpha) {
  if (!color) return `rgba(255,255,255,${alpha})`;
  if (color.startsWith('#')) {
    const hex = color.slice(1);
    const full = hex.length === 3 ? hex.split('').map(char => char + char).join('') : hex;
    const value = Number.parseInt(full, 16);
    return `rgba(${(value >> 16) & 255},${(value >> 8) & 255},${value & 255},${alpha})`;
  }
  const channels = color.match(/[\d.]+/g);
  if (channels && channels.length >= 3) {
    return `rgba(${channels[0]},${channels[1]},${channels[2]},${alpha})`;
  }
  return color;
}

function resolvePalette() {
  const probe = document.createElement('span');
  probe.style.position = 'fixed';
  probe.style.visibility = 'hidden';
  document.body.appendChild(probe);
  const resolve = token => {
    probe.style.color = `var(${token})`;
    return getComputedStyle(probe).color;
  };
  const palette = {
    background: resolve('--color-bg'),
    depth: resolve('--color-surface-sunken'),
    light: resolve('--color-accent'),
    cyan: resolve('--color-info'),
    violet: resolve('--color-moments'),
    warm: resolve('--color-warning')
  };
  probe.remove();
  return palette;
}

function phaseCopy() {
  if (state.mode === 'sighing') {
    if (state.phase === 'inhale1') return ['Gather', 'A gentle first breath'];
    if (state.phase === 'inhale2') return ['And again', 'A small second breath'];
    if (state.phase === 'exhale') return ['Release', 'Long and unhurried'];
    return ['Rest', 'Let the next breath arrive'];
  }
  return state.phase === 'inhale'
    ? ['Gather', 'Let the breath arrive']
    : ['Release', 'Long and unhurried'];
}

function updateRitualUI() {
  const remaining = Math.max(0, state.totalMs - state.elapsedMs);
  elements.timeRemaining.textContent = formatTime(remaining);
  const [title, detail] = phaseCopy();
  elements.phaseText.textContent = title;
  elements.phaseDetail.textContent = detail;
  elements.phaseKicker.textContent = state.mode === 'coherent' ? 'Long exhale' : 'Two-part inhale';
  const progress = clamp(state.elapsedMs / state.totalMs, 0, 1);
  elements.settleLabel.textContent = progress < 0.2 ? 'Arriving' : progress < 0.8 ? 'Settling' : 'Stillness';
}

function formatTime(milliseconds) {
  const seconds = Math.ceil(milliseconds / 1000);
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(seconds % 60).padStart(2, '0')}`;
}

function startRitual(preValue) {
  state.pre = preValue;
  state.elapsedMs = 0;
  state.breathClockMs = 0;
  state.cycleIndex = 0;
  state.sessionStartedAt = new Date().toISOString();
  persistPreReport(preValue);
  setView('ritual');
  updateModeUI();
  updateRitualUI();
  elements.liveStatus.textContent = 'The five minute Flow ritual has begun.';
}

function finishRitual() {
  if (state.view !== 'ritual') return;
  state.paused = false;
  hideControls();
  elements.pausePanel.hidden = true;
  setView('check-out');
  elements.liveStatus.textContent = 'The ritual is complete. Choose how settled you feel now.';
}

function finishCheckOut(value) {
  state.post = value;
  persistCompletedSession();
  elements.comparison.textContent = `You arrived at ${state.pre}. You are leaving at ${state.post}.`;
  if (rideId) {
    elements.journalRide.href = `index.html?ride=${encodeURIComponent(rideId)}`;
    elements.journalRide.hidden = false;
    elements.done.hidden = true;
  } else {
    elements.journalRide.hidden = true;
    elements.done.hidden = false;
  }
  setView('complete');
  elements.liveStatus.textContent = elements.comparison.textContent;
}

function togglePause(force) {
  if (state.view !== 'ritual') return;
  state.paused = typeof force === 'boolean' ? force : !state.paused;
  elements.pausePanel.hidden = !state.paused;
  elements.pause.setAttribute('aria-label', state.paused ? 'Resume ritual' : 'Pause ritual');
  elements.liveStatus.textContent = state.paused ? 'Flow paused.' : 'Flow resumed.';
  if (state.paused) hideControls();
  if (!state.paused) state.lastFrameAt = performance.now();
}

function showControls() {
  if (state.view !== 'ritual' || state.paused) return;
  elements.controls.hidden = false;
  elements.controlsToggle.setAttribute('aria-expanded', 'true');
  window.clearTimeout(state.controlsTimer);
  state.controlsTimer = window.setTimeout(hideControls, 7000);
}

function hideControls() {
  window.clearTimeout(state.controlsTimer);
  elements.controls.hidden = true;
  elements.controlsToggle.setAttribute('aria-expanded', 'false');
}

function updateModeUI() {
  document.querySelectorAll('[data-mode]').forEach(button => {
    button.setAttribute('aria-checked', String(button.dataset.mode === state.mode));
  });
  elements.paceControl.hidden = state.mode !== 'coherent';
  elements.paceDescription.textContent = `${(state.targetCycleMs / 1000).toFixed(1).replace('.0', '')} seconds per cycle`;
}

function setMode(mode) {
  if (mode !== 'coherent' && mode !== 'sighing') return;
  state.mode = mode;
  state.breathClockMs = 0;
  state.cycleIndex = 0;
  persistSettings();
  updateModeUI();
  updateRitualUI();
  elements.liveStatus.textContent = mode === 'coherent' ? 'Coherent breathing selected.' : 'Cyclic sighing selected.';
}

function nudgePace(direction) {
  state.targetCycleMs = clamp(
    state.targetCycleMs + direction * FLOW_CONFIG.coherent.stepMs,
    FLOW_CONFIG.coherent.minTargetMs,
    FLOW_CONFIG.coherent.maxTargetMs
  );
  persistSettings();
  updateModeUI();
  elements.liveStatus.textContent = `Target pace is ${(state.targetCycleMs / 1000).toFixed(1).replace('.0', '')} seconds per cycle.`;
  showControls();
}

function createAudio() {
  if (audio) return audio;
  const AudioContext = window.AudioContext || window.webkitAudioContext;
  if (!AudioContext) return null;
  const audioContext = new AudioContext();
  const gain = audioContext.createGain();
  const low = audioContext.createOscillator();
  const high = audioContext.createOscillator();
  low.type = 'sine';
  high.type = 'sine';
  low.frequency.value = 96;
  high.frequency.value = 144;
  gain.gain.value = 0;
  low.connect(gain);
  high.connect(gain);
  gain.connect(audioContext.destination);
  low.start();
  high.start();
  audio = { context: audioContext, gain, low, high };
  return audio;
}

async function toggleSound() {
  state.soundEnabled = !state.soundEnabled;
  if (state.soundEnabled) {
    const layer = createAudio();
    if (!layer) {
      state.soundEnabled = false;
      elements.liveStatus.textContent = 'Sound is not available in this browser.';
    } else {
      await layer.context.resume();
    }
  }
  elements.sound.setAttribute('aria-pressed', String(state.soundEnabled));
  elements.sound.querySelector('span:last-child').textContent = state.soundEnabled ? 'Sound on' : 'Sound off';
  updateAudio();
}

function updateAudio() {
  if (!audio) return;
  const now = audio.context.currentTime;
  const target = state.soundEnabled && !state.paused && !state.hidden && state.view === 'ritual'
    ? 0.018 + state.envelope * 0.018
    : 0;
  audio.gain.gain.setTargetAtTime(target, now, 0.12);
  audio.high.frequency.setTargetAtTime(132 + state.envelope * 28, now, 0.2);
}

function nativeMessage(type, payload = {}) {
  const handler = window.webkit?.messageHandlers?.flowBridge;
  if (!handler?.postMessage) return false;
  handler.postMessage({ type, rideId: rideId || null, ...payload });
  return true;
}

function exitDestination() {
  return rideId ? `index.html?ride=${encodeURIComponent(rideId)}` : 'dashboard.html';
}

function leaveFlow(destination = exitDestination()) {
  if (nativeMessage('close', { destination })) {
    dispose();
    return;
  }
  dispose();
  window.location.assign(destination);
}

function exitFlow() {
  leaveFlow();
}

function dispose() {
  if (state.disposed) return;
  state.disposed = true;
  cancelAnimationFrame(state.rafId);
  window.clearTimeout(state.controlsTimer);
  listeners.splice(0).forEach(remove => remove());
  if (audio) {
    try {
      audio.low.stop();
      audio.high.stop();
      audio.context.close();
    } catch (error) {
      // Audio may already be closed by the browser lifecycle.
    }
    audio = null;
  }
  state.particles.length = 0;
  context = null;
}

function handleVisibility() {
  state.hidden = document.hidden;
  if (state.hidden) {
    cancelAnimationFrame(state.rafId);
    updateAudio();
  } else if (!state.disposed) {
    state.lastFrameAt = performance.now();
    state.rafId = requestAnimationFrame(frame);
  }
}

function handleKeydown(event) {
  if (event.key === 'Escape') {
    event.preventDefault();
    exitFlow();
    return;
  }
  if (event.code === 'Space' && state.view === 'ritual') {
    event.preventDefault();
    togglePause();
    return;
  }
  if (/^[1-5]$/.test(event.key)) {
    const value = Number(event.key);
    if (state.view === 'check-in') startRitual(value);
    else if (state.view === 'check-out') finishCheckOut(value);
  }
}

function bindEvents() {
  on(window, 'resize', resizeCanvas);
  on(window, 'pagehide', dispose, { once: true });
  on(document, 'visibilitychange', handleVisibility);
  on(document, 'keydown', handleKeydown);
  on(root, 'pointerdown', event => {
    if (event.target === canvas && state.view === 'ritual' && elements.controls.hidden) showControls();
  });
  on(elements.close, 'click', exitFlow);
  on(elements.journalRide, 'click', event => {
    event.preventDefault();
    leaveFlow(elements.journalRide.href);
  });
  on(elements.done, 'click', event => {
    event.preventDefault();
    leaveFlow(elements.done.href);
  });
  on(elements.controlsToggle, 'click', () => elements.controls.hidden ? showControls() : hideControls());
  on(elements.controlsDismiss, 'click', hideControls);
  on(elements.pause, 'click', () => togglePause());
  on(elements.resume, 'click', () => togglePause(false));
  on(elements.pauseEnd, 'click', finishRitual);
  on(elements.endEarly, 'click', finishRitual);
  on(elements.extend, 'click', () => {
    state.totalMs += FLOW_CONFIG.extensionMs;
    elements.liveStatus.textContent = 'Five minutes added.';
    updateRitualUI();
    showControls();
  });
  on(elements.sound, 'click', toggleSound);
  on(elements.paceFaster, 'click', () => nudgePace(-1));
  on(elements.paceSlower, 'click', () => nudgePace(1));

  document.querySelectorAll('[data-report="pre"] button').forEach(button => {
    on(button, 'click', () => startRitual(Number(button.dataset.value)));
  });
  document.querySelectorAll('[data-report="post"] button').forEach(button => {
    on(button, 'click', () => finishCheckOut(Number(button.dataset.value)));
  });
  document.querySelectorAll('[data-mode]').forEach(button => {
    on(button, 'click', () => setMode(button.dataset.mode));
  });
}

function initialise() {
  if (!canvas || !context || !root) return;
  elements.controlsToggle.hidden = true;
  bindEvents();
  updateModeUI();
  resizeCanvas();
  state.rafId = requestAnimationFrame(frame);
}

initialise();
