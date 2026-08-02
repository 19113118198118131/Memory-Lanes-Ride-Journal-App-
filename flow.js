import {
  FLOW_CONSTANTS,
  clamp,
  createGameState,
  finishSession,
  resizeViewport,
  sampleRoadAtDistance,
  stepGame,
  updateRoad,
} from './flow-engine.js';
import { FlowAudio } from './flow-audio.js';
import { loadFlowData, recordFlowSession, saveFlowData } from './flow-storage.js';
import { FlowRenderer } from './flow-renderer.js';
import { FlowPlayCanvasRenderer, supportsFlow3D } from './flow-playcanvas-renderer.js';

const elements = {
  root: document.querySelector('#flow-root'),
  canvas: document.querySelector('#flow-canvas'),
  close: document.querySelector('#flow-close'),
  intro: document.querySelector('#flow-intro'),
  game: document.querySelector('#flow-game'),
  results: document.querySelector('#flow-results'),
  settingsButton: document.querySelector('#flow-settings-button'),
  settings: document.querySelector('#flow-settings'),
  settingsClose: document.querySelector('#flow-settings-close'),
  instructions: document.querySelector('#flow-instructions'),
  instructionsClose: document.querySelector('#flow-instructions-close'),
  instructionsDone: document.querySelector('#flow-instructions-done'),
  howToPlay: document.querySelector('#flow-how-to-play'),
  aboutButton: document.querySelector('#flow-about'),
  safetyGate: document.querySelector('#flow-safety-gate'),
  safetyBegin: document.querySelector('#flow-safety-begin'),
  safetyCancel: document.querySelector('#flow-safety-cancel'),
  introBest: document.querySelector('#flow-intro-best'),
  introChain: document.querySelector('#flow-intro-chain'),
  pauseButton: document.querySelector('#flow-pause'),
  pauseOverlay: document.querySelector('#flow-pause-overlay'),
  continueButton: document.querySelector('#flow-continue'),
  restartButton: document.querySelector('#flow-restart'),
  leaveButton: document.querySelector('#flow-leave'),
  playAgain: document.querySelector('#flow-play-again'),
  returnButton: document.querySelector('#flow-return'),
  timeLabel: document.querySelector('#flow-time-label'),
  time: document.querySelector('#flow-time'),
  rhythm: document.querySelector('#flow-rhythm'),
  flowValue: document.querySelector('#flow-value'),
  meter: document.querySelector('.flow-meter-track'),
  meterFill: document.querySelector('#flow-meter-fill'),
  score: document.querySelector('#flow-score'),
  chain: document.querySelector('#flow-chain'),
  chainValue: document.querySelector('#flow-chain-value'),
  breathGuide: document.querySelector('#flow-breath-guide'),
  breathPhase: document.querySelector('#flow-breath-phase'),
  breathDetail: document.querySelector('#flow-breath-detail'),
  stageLabel: document.querySelector('#flow-stage-label'),
  apexCallout: document.querySelector('#flow-apex-callout'),
  controlsHint: document.querySelector('#flow-controls-hint'),
  resultTitle: document.querySelector('#flow-result-title'),
  resultSubtitle: document.querySelector('#flow-result-subtitle'),
  resultFlow: document.querySelector('#flow-result-flow'),
  resultSmoothness: document.querySelector('#flow-result-smoothness'),
  resultApex: document.querySelector('#flow-result-apex'),
  resultCorners: document.querySelector('#flow-result-corners'),
  resultStreak: document.querySelector('#flow-result-streak'),
  personalBest: document.querySelector('#flow-personal-best'),
  sound: document.querySelector('#flow-sound'),
  haptics: document.querySelector('#flow-haptics'),
  sensitivity: document.querySelector('#flow-sensitivity'),
  lineGuide: document.querySelector('#flow-line-guide'),
  breathingGuide: document.querySelector('#flow-breathing-guide'),
  breathingPace: document.querySelector('#flow-breathing-pace'),
  voiceGuidance: document.querySelector('#flow-voice-guidance'),
  breathHaptics: document.querySelector('#flow-breath-haptics'),
  reducedEffects: document.querySelector('#flow-reduced-effects'),
  quality: document.querySelector('#flow-quality'),
  motorcycle: document.querySelector('#flow-motorcycle'),
  liveRegion: document.querySelector('#flow-live-region'),
};

function createRenderer(canvas) {
  if (supportsFlow3D()) {
    try {
      document.documentElement.dataset.flowRenderer = 'playcanvas';
      return new FlowPlayCanvasRenderer(canvas);
    } catch (error) {
      console.warn('Flow 3D renderer unavailable; using Canvas 2D.', error);
    }
  }

  document.documentElement.dataset.flowRenderer = 'canvas2d';
  return new FlowRenderer(canvas);
}

const renderer = createRenderer(elements.canvas);
const audio = new FlowAudio();
const reducedMotionQuery = matchMedia('(prefers-reduced-motion: reduce)');
let savedData = loadFlowData();
let gameState = createGameState({ seed: 'flow-idle-road' });
let phase = 'intro';
let activeMode = 'quick';
let pendingMode = 'quick';
let currentInput = 0;
let pointerActive = false;
let lastFrameTime = performance.now();
let animationFrame = 0;
let apexCalloutTimer = 0;
let controlsHintTimer = 0;
let result = null;
let lastBreathPhase = '';
let lastBreathCycle = -1;
let lastSessionStage = '';
const pressedKeys = new Set();

function setPhase(nextPhase) {
  phase = nextPhase;
  elements.root.dataset.phase = nextPhase;
  elements.intro.hidden = nextPhase !== 'intro';
  elements.game.hidden = nextPhase !== 'playing';
  elements.results.hidden = nextPhase !== 'results';
}

function updateIntroRecords() {
  const bestFlow = Math.max(
    savedData.bests.quick.flowScore || 0,
    savedData.bests.endless.flowScore || 0,
  );
  const bestChain = Math.max(
    savedData.bests.quick.streak || 0,
    savedData.bests.endless.streak || 0,
  );
  if (elements.introBest) elements.introBest.textContent = bestFlow ? String(bestFlow) : '--';
  if (elements.introChain) elements.introChain.textContent = bestChain ? String(bestChain) : '--';
}

function createSessionSeed() {
  if (globalThis.crypto?.getRandomValues) {
    const value = new Uint32Array(2);
    crypto.getRandomValues(value);
    return `${value[0].toString(16)}-${value[1].toString(16)}`;
  }
  return `${Date.now()}-${Math.random()}`;
}

function applySettings() {
  const settings = savedData.settings;
  elements.sound.checked = settings.sound;
  elements.haptics.checked = settings.haptics;
  elements.sensitivity.value = settings.inputSensitivity;
  elements.lineGuide.value = settings.lineGuide;
  elements.breathingGuide.value = settings.breathingGuide;
  elements.breathingPace.value = settings.breathingPace;
  elements.voiceGuidance.checked = settings.voiceGuidance;
  elements.breathHaptics.checked = settings.breathHaptics;
  elements.reducedEffects.checked = settings.reducedEffects;
  elements.quality.value = settings.quality;
  elements.motorcycle.value = settings.motorcycle;
  updatePaceButtons(settings.breathingPace);
  audio.setEnabled(settings.sound);
}

function persistSettings() {
  savedData.settings = {
    sound: elements.sound.checked,
    haptics: elements.haptics.checked,
    inputSensitivity: elements.sensitivity.value,
    lineGuide: elements.lineGuide.value,
    breathingGuide: elements.breathingGuide.value,
    breathingPace: elements.breathingPace.value,
    voiceGuidance: elements.voiceGuidance.checked,
    breathHaptics: elements.breathHaptics.checked,
    reducedEffects: elements.reducedEffects.checked,
    quality: elements.quality.value,
    motorcycle: elements.motorcycle.value,
  };
  savedData = saveFlowData(savedData);
  audio.setEnabled(savedData.settings.sound);
  updatePaceButtons(savedData.settings.breathingPace);
  if (gameState) gameState.settings.inputSensitivity = savedData.settings.inputSensitivity;
  announce('Flow settings updated');
}

function updatePaceButtons(pace) {
  document.querySelectorAll('[data-breath-pace]').forEach(button => {
    const selected = button.dataset.breathPace === pace;
    button.classList.toggle('is-selected', selected);
    button.setAttribute('aria-checked', String(selected));
  });
}

function requestSession(mode) {
  pendingMode = mode === 'endless' ? 'endless' : 'quick';
  elements.safetyBegin.textContent = pendingMode === 'quick' ? 'Yes, begin reset' : 'Yes, open the road';
  updatePaceButtons(savedData.settings.breathingPace);
  openOverlay(elements.safetyGate);
}

function announce(message) {
  elements.liveRegion.textContent = '';
  requestAnimationFrame(() => { elements.liveRegion.textContent = message; });
}

function nativeMessage(type, value = null) {
  try {
    globalThis.webkit?.messageHandlers?.flowBridge?.postMessage({ type, value });
  } catch {}
}

function haptic(kind = 'selection') {
  if (!savedData.settings.haptics) return;
  nativeMessage('haptic', kind);
  if (!globalThis.webkit?.messageHandlers?.flowBridge && navigator.vibrate) {
    navigator.vibrate(kind === 'success' ? 12 : 8);
  }
}

function closeFlow() {
  nativeMessage('close');
  if (globalThis.webkit?.messageHandlers?.flowBridge) return;
  if (history.length > 1 && document.referrer) history.back();
  else location.href = 'dashboard.html';
}

function openOverlay(element) {
  element.hidden = false;
  const focusable = element.querySelector('button, select, input');
  requestAnimationFrame(() => focusable?.focus());
}

function closeOverlay(element) {
  element.hidden = true;
}

async function startSession(mode) {
  activeMode = mode === 'endless' ? 'endless' : 'quick';
  result = null;
  currentInput = 0;
  pointerActive = false;
  gameState = createGameState({
    mode: activeMode,
    seed: createSessionSeed(),
    inputSensitivity: savedData.settings.inputSensitivity,
    breathingGuide: savedData.settings.breathingGuide,
    breathingPace: savedData.settings.breathingPace,
  });
  closeOverlay(elements.safetyGate);
  lastBreathPhase = gameState.breathing.phase;
  lastBreathCycle = gameState.breathing.cycleIndex;
  lastSessionStage = '';
  setPhase('playing');
  elements.pauseOverlay.hidden = true;
  elements.controlsHint.textContent = activeMode === 'quick' ? 'No score. Just arrive.' : 'Breathe. Follow the road.';
  elements.controlsHint.classList.remove('is-hidden');
  clearTimeout(controlsHintTimer);
  controlsHintTimer = setTimeout(() => {
    elements.controlsHint.textContent = 'Hold the rhythm';
  }, 3200);
  await audio.unlock();
  audio.setPaused(false);
  haptic('selection');
  announce(`${activeMode === 'quick' ? 'Quick Reset' : 'Open Road'} started. Drag gently left or right.`);
  lastFrameTime = performance.now();
  updateHud();
  updateGuidance();
}

function setPaused(paused, reason = 'Roadside pause') {
  if (phase !== 'playing' || gameState.completed) return;
  gameState.paused = paused;
  elements.pauseOverlay.hidden = !paused;
  audio.setPaused(paused);
  if (paused) {
    pressedKeys.clear();
    pointerActive = false;
    announce(reason);
  } else {
    lastFrameTime = performance.now();
    announce('Flow continued');
  }
}

function leaveSession() {
  gameState.paused = false;
  closeOverlay(elements.pauseOverlay);
  gameState = createGameState({ seed: 'flow-idle-road' });
  currentInput = 0;
  setPhase('intro');
  audio.setPaused(false);
  globalThis.speechSynthesis?.cancel();
}

function finishCurrentSession() {
  result = finishSession(gameState, gameState.completionReason || 'complete');
  const priorBest = savedData.bests[result.mode].flowScore || 0;
  savedData = recordFlowSession(savedData, result);
  updateIntroRecords();
  elements.resultTitle.textContent = resultMessage(result.flowScore);
  elements.resultSubtitle.textContent = result.reason === 'flow-ended'
    ? 'The rhythm slipped. A quieter second run may click.'
    : 'Reset complete.';
  elements.resultFlow.textContent = String(result.flowScore);
  elements.resultSmoothness.textContent = `${result.smoothness}%`;
  elements.resultApex.textContent = `${result.cleanApexRate}%`;
  elements.resultCorners.textContent = String(result.corners);
  elements.resultStreak.textContent = String(result.longestStreak);
  elements.personalBest.hidden = result.flowScore <= priorBest;
  setPhase('results');
  audio.complete();
  haptic('success');
  announce(`${elements.resultTitle.textContent}. Session Flow ${result.flowScore}.`);
}

function resultMessage(score) {
  if (score >= 90) return 'Silky smooth';
  if (score >= 75) return 'In the rhythm';
  if (score >= 60) return 'Calm and composed';
  if (score >= 40) return 'Finding the line';
  return 'A quieter second run may click';
}

function rhythmLabel(streak) {
  if (streak >= 15) return 'One with the road';
  if (streak >= 10) return 'Locked in';
  if (streak >= 6) return 'Flowing';
  if (streak >= 3) return 'In rhythm';
  return gameState.elapsed < 5 ? 'Settle in' : 'Follow the glow';
}

function formatTime(seconds) {
  const total = Math.max(0, Math.ceil(seconds));
  const minutes = Math.floor(total / 60);
  return `${minutes}:${String(total % 60).padStart(2, '0')}`;
}

function updateHud() {
  const remaining = activeMode === 'quick'
    ? Math.max(0, gameState.duration - gameState.elapsed)
    : gameState.elapsed;
  elements.timeLabel.textContent = activeMode === 'quick' ? 'Time' : 'Road';
  elements.time.textContent = formatTime(remaining);
  elements.score.textContent = String(Math.round(gameState.metrics.score));
  elements.flowValue.textContent = String(Math.round(gameState.metrics.flow));
  elements.chainValue.textContent = String(gameState.metrics.currentStreak);
  elements.chain.classList.toggle('is-live', gameState.metrics.currentStreak >= 3);
  elements.rhythm.textContent = rhythmLabel(gameState.metrics.currentStreak);
  elements.meterFill.style.width = `${gameState.metrics.flow}%`;
  elements.meterFill.style.backgroundColor = gameState.metrics.flow < 28 ? '#ffd60a' : '#2ee6c0';
  elements.meter.setAttribute('aria-valuenow', String(Math.round(gameState.metrics.flow)));
  elements.root.dataset.flowState = gameState.metrics.flow < 28
    ? 'low'
    : gameState.metrics.flow >= FLOW_CONSTANTS.highFlowThreshold ? 'high' : 'steady';
  audio.setFlow(gameState.metrics.flow);
}

function speakGuidance(message) {
  if (!savedData.settings.voiceGuidance || !globalThis.speechSynthesis || !message) return;
  speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(message);
  utterance.rate = 0.82;
  utterance.pitch = 0.88;
  utterance.volume = 0.55;
  speechSynthesis.speak(utterance);
}

function updateGuidance() {
  const stage = gameState.phase;
  const breathing = gameState.breathing;
  const stageChanged = stage !== lastSessionStage;
  elements.root.dataset.stage = stage;
  elements.root.dataset.breathPhase = breathing.phase;
  elements.breathGuide.classList.toggle('is-subtle', stage === 'flow' || savedData.settings.breathingGuide === 'subtle');
  elements.breathGuide.hidden = savedData.settings.breathingGuide === 'off' && !['arrive', 'land'].includes(stage);

  if (stageChanged) {
    lastSessionStage = stage;
    if (stage === 'arrive') {
      elements.stageLabel.textContent = 'Arrive';
      elements.breathPhase.textContent = 'Let the ride settle.';
      elements.breathDetail.textContent = 'Breathe normally for a moment';
    } else if (stage === 'follow') {
      elements.stageLabel.textContent = 'Follow';
      elements.breathDetail.textContent = 'Let the road set the pace';
    } else if (stage === 'flow') {
      elements.stageLabel.textContent = 'Flow';
      elements.breathDetail.textContent = 'One breath. One corner. One smooth decision.';
    } else if (stage === 'land') {
      elements.stageLabel.textContent = 'Land';
      elements.breathPhase.textContent = 'Let the rhythm soften.';
      elements.breathDetail.textContent = 'The road is settling';
    } else if (stage === 'open-road') {
      elements.stageLabel.textContent = 'Open road';
      elements.breathDetail.textContent = 'Stay only as long as it feels good';
    }
  }

  const phaseChanged = stageChanged || breathing.phase !== lastBreathPhase || breathing.cycleIndex !== lastBreathCycle;
  const explicitGuidance = stage === 'follow' && breathing.cycleIndex < 2 && savedData.settings.breathingGuide === 'guided';
  if (explicitGuidance) {
    elements.breathPhase.textContent = breathing.phase === 'inhale' ? 'Breathe in gently' : 'Let it go slowly';
  } else if (stage === 'flow' || stage === 'open-road') {
    elements.breathPhase.textContent = breathing.phase === 'inhale' ? 'See the road' : 'Move smoothly';
  }

  if (phaseChanged && ['follow', 'flow', 'open-road'].includes(stage)) {
    if (savedData.settings.breathHaptics) haptic(breathing.phase === 'inhale' ? 'selection' : 'breath-out');
    if (explicitGuidance) speakGuidance(elements.breathPhase.textContent);
    lastBreathPhase = breathing.phase;
    lastBreathCycle = breathing.cycleIndex;
  }
  audio.setBreathing(breathing.visualEnvelope, breathing.phase);
}

function showApex(resultValue) {
  if (!resultValue) return;
  elements.apexCallout.textContent = resultValue.label;
  elements.apexCallout.dataset.grade = resultValue.grade;
  elements.apexCallout.classList.add('is-visible');
  clearTimeout(apexCalloutTimer);
  apexCalloutTimer = setTimeout(() => elements.apexCallout.classList.remove('is-visible'), 1050);
  if (resultValue.score >= 2) {
    audio.apex(resultValue.grade);
    haptic('selection');
  }
  if ([3, 6, 10, 15].includes(gameState.metrics.currentStreak)) {
    audio.streak();
  }
}

function resizeCanvas() {
  const rect = elements.canvas.getBoundingClientRect();
  const dpr = Math.min(2, globalThis.devicePixelRatio || 1);
  renderer.resize(rect.width, rect.height, dpr);
  resizeViewport(gameState, rect.width, rect.height, dpr);
}

function inputFromPointer(event) {
  const rect = elements.canvas.getBoundingClientRect();
  return clamp(((event.clientX - rect.left) / Math.max(1, rect.width) - 0.5) * 2, -1, 1);
}

function onPointerDown(event) {
  if (phase !== 'playing' || gameState.paused) return;
  const rect = elements.canvas.getBoundingClientRect();
  if ((event.clientY - rect.top) / Math.max(1, rect.height) < 0.3) return;
  pointerActive = true;
  currentInput = inputFromPointer(event);
  elements.canvas.setPointerCapture?.(event.pointerId);
  event.preventDefault();
  elements.controlsHint.classList.add('is-hidden');
  audio.unlock();
}

function onPointerMove(event) {
  if (!pointerActive || phase !== 'playing' || gameState.paused) return;
  currentInput = inputFromPointer(event);
  event.preventDefault();
}

function onPointerEnd(event) {
  pointerActive = false;
  if (elements.canvas.hasPointerCapture?.(event.pointerId)) {
    elements.canvas.releasePointerCapture(event.pointerId);
  }
}

function onKeyDown(event) {
  const key = event.key.toLowerCase();
  if (['arrowleft', 'arrowright', 'a', 'd', ' ', 'escape'].includes(key)) event.preventDefault();
  if (key === ' ' && phase === 'playing') {
    setPaused(!gameState.paused);
    return;
  }
  if (key === 'escape') {
    if (!elements.settings.hidden) closeOverlay(elements.settings);
    else if (!elements.instructions.hidden) closeOverlay(elements.instructions);
    else if (!elements.safetyGate.hidden) closeOverlay(elements.safetyGate);
    else if (phase === 'playing') setPaused(true);
    return;
  }
  pressedKeys.add(key);
}

function onKeyUp(event) {
  pressedKeys.delete(event.key.toLowerCase());
}

function updateKeyboardInput(deltaTime) {
  if (pointerActive) return;
  const left = pressedKeys.has('arrowleft') || pressedKeys.has('a');
  const right = pressedKeys.has('arrowright') || pressedKeys.has('d');
  const direction = (right ? 1 : 0) - (left ? 1 : 0);
  if (direction) currentInput = clamp(currentInput + direction * deltaTime * 1.35, -1, 1);
}

function frame(timestamp) {
  const deltaTime = Math.max(0, (timestamp - lastFrameTime) / 1000);
  lastFrameTime = timestamp;
  resizeCanvas();

  if (phase === 'playing' && !gameState.paused) {
    updateKeyboardInput(Math.min(deltaTime, FLOW_CONSTANTS.maximumDeltaTime));
    const frameResult = stepGame(gameState, currentInput, deltaTime);
    updateHud();
    updateGuidance();
    if (frameResult.apex) showApex(frameResult.apex);
    if (gameState.completed) finishCurrentSession();
  } else if (phase === 'intro') {
    updateRoad(gameState, Math.min(deltaTime, 1 / 60) * 0.32);
    const idleRoad = sampleRoadAtDistance(gameState, gameState.road.travelled);
    gameState.bike.x += (idleRoad.targetX - gameState.bike.x) * 0.02;
  } else if (phase === 'results') {
    updateRoad(gameState, Math.min(deltaTime, 1 / 60) * 0.12);
  }

  renderer.render(gameState, timestamp, {
    ...savedData.settings,
    reducedEffects: savedData.settings.reducedEffects || reducedMotionQuery.matches,
  }, phase);
  animationFrame = requestAnimationFrame(frame);
}

document.querySelectorAll('[data-mode]').forEach(button => {
  button.addEventListener('click', () => requestSession(button.dataset.mode));
});

document.querySelectorAll('[data-breath-pace]').forEach(button => {
  button.addEventListener('click', () => {
    elements.breathingPace.value = button.dataset.breathPace;
    persistSettings();
    updatePaceButtons(button.dataset.breathPace);
  });
});

elements.canvas.addEventListener('pointerdown', onPointerDown, { passive: false });
elements.canvas.addEventListener('pointermove', onPointerMove, { passive: false });
elements.canvas.addEventListener('pointerup', onPointerEnd);
elements.canvas.addEventListener('pointercancel', onPointerEnd);
window.addEventListener('keydown', onKeyDown, { passive: false });
window.addEventListener('keyup', onKeyUp);
window.addEventListener('resize', resizeCanvas);
window.addEventListener('orientationchange', () => {
  if (phase === 'playing' && !gameState.paused) setPaused(true, 'Flow paused while the screen changed orientation');
  setTimeout(resizeCanvas, 120);
});
window.addEventListener('blur', () => {
  if (phase === 'playing' && !gameState.paused) setPaused(true, 'Flow paused during an interruption');
});
document.addEventListener('visibilitychange', () => {
  if (document.hidden && phase === 'playing' && !gameState.paused) {
    setPaused(true, 'Flow paused while Memory Lanes was in the background');
  }
});

elements.close.addEventListener('click', () => {
  if (phase === 'playing' && !gameState.paused) setPaused(true);
  else closeFlow();
});
elements.returnButton.addEventListener('click', closeFlow);
elements.pauseButton.addEventListener('click', () => setPaused(true));
elements.continueButton.addEventListener('click', () => setPaused(false));
elements.restartButton.addEventListener('click', () => startSession(activeMode));
elements.leaveButton.addEventListener('click', leaveSession);
elements.playAgain.addEventListener('click', () => startSession('endless'));
elements.safetyBegin.addEventListener('click', () => startSession(pendingMode));
elements.safetyCancel.addEventListener('click', () => closeOverlay(elements.safetyGate));
elements.settingsButton.addEventListener('click', () => openOverlay(elements.settings));
elements.settingsClose.addEventListener('click', () => closeOverlay(elements.settings));
elements.howToPlay.addEventListener('click', () => openOverlay(elements.instructions));
elements.aboutButton.addEventListener('click', () => openOverlay(elements.instructions));
elements.instructionsClose.addEventListener('click', () => closeOverlay(elements.instructions));
elements.instructionsDone.addEventListener('click', () => closeOverlay(elements.instructions));
for (const input of [
  elements.sound,
  elements.haptics,
  elements.sensitivity,
  elements.lineGuide,
  elements.breathingGuide,
  elements.breathingPace,
  elements.voiceGuidance,
  elements.breathHaptics,
  elements.reducedEffects,
  elements.quality,
  elements.motorcycle,
]) {
  input.addEventListener('change', persistSettings);
}

if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
  addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}

applySettings();
updateIntroRecords();
resizeCanvas();
setPhase('intro');
animationFrame = requestAnimationFrame(frame);

addEventListener('pagehide', () => {
  cancelAnimationFrame(animationFrame);
  audio.dispose();
}, { once: true });
