export const FLOW_STORAGE_KEY = 'memoryLanes.flow.v1';
export const FLOW_STORAGE_VERSION = 1;
export const FLOW_SESSION_LIMIT = 20;

export const DEFAULT_FLOW_DATA = Object.freeze({
  version: FLOW_STORAGE_VERSION,
  settings: {
    sound: true,
    haptics: true,
    inputSensitivity: 'balanced',
    lineGuide: 'subtle',
    reducedEffects: false,
    breathingGuide: 'guided',
    breathingPace: 'settle',
    voiceGuidance: false,
    breathHaptics: true,
    quality: 'balanced',
    motorcycle: 'sport',
  },
  bests: {
    quick: { score: 0, flowScore: 0, smoothness: 0, cleanApexRate: 0, streak: 0 },
    endless: { score: 0, flowScore: 0, durationSeconds: 0, streak: 0 },
  },
  sessions: [],
});

function cloneDefaults() {
  return JSON.parse(JSON.stringify(DEFAULT_FLOW_DATA));
}

function safeBoolean(value, fallback) {
  return typeof value === 'boolean' ? value : fallback;
}

export function normaliseFlowData(candidate) {
  const data = cloneDefaults();
  if (!candidate || typeof candidate !== 'object') return data;
  const settings = candidate.settings && typeof candidate.settings === 'object'
    ? candidate.settings
    : {};
  data.settings.sound = safeBoolean(settings.sound, data.settings.sound);
  data.settings.haptics = safeBoolean(settings.haptics, data.settings.haptics);
  data.settings.reducedEffects = safeBoolean(settings.reducedEffects, data.settings.reducedEffects);
  data.settings.voiceGuidance = safeBoolean(settings.voiceGuidance, data.settings.voiceGuidance);
  data.settings.breathHaptics = safeBoolean(settings.breathHaptics, data.settings.breathHaptics);
  if (['gentle', 'balanced', 'responsive'].includes(settings.inputSensitivity)) {
    data.settings.inputSensitivity = settings.inputSensitivity;
  }
  if (['full', 'subtle', 'off'].includes(settings.lineGuide)) {
    data.settings.lineGuide = settings.lineGuide;
  }
  if (['guided', 'subtle', 'off'].includes(settings.breathingGuide)) {
    data.settings.breathingGuide = settings.breathingGuide;
  }
  if (['gentle', 'balanced', 'settle'].includes(settings.breathingPace)) {
    data.settings.breathingPace = settings.breathingPace;
  }
  if (['low', 'balanced', 'high'].includes(settings.quality)) {
    data.settings.quality = settings.quality;
  }
  if (['sport', 'adventure', 'naked', 'cruiser', 'touring', 'classic'].includes(settings.motorcycle)) {
    data.settings.motorcycle = settings.motorcycle;
  }

  for (const mode of ['quick', 'endless']) {
    const best = candidate.bests?.[mode];
    if (!best || typeof best !== 'object') continue;
    for (const key of Object.keys(data.bests[mode])) {
      if (Number.isFinite(best[key]) && best[key] >= 0) data.bests[mode][key] = best[key];
    }
  }
  if (Array.isArray(candidate.sessions)) {
    data.sessions = candidate.sessions
      .filter(session => session && typeof session === 'object' && ['quick', 'endless'].includes(session.mode))
      .slice(-FLOW_SESSION_LIMIT);
  }
  return data;
}

export function loadFlowData(storage = globalThis.localStorage) {
  if (!storage || typeof storage.getItem !== 'function') return cloneDefaults();
  try {
    const raw = storage.getItem(FLOW_STORAGE_KEY);
    if (!raw) return cloneDefaults();
    return normaliseFlowData(JSON.parse(raw));
  } catch {
    return cloneDefaults();
  }
}

export function saveFlowData(data, storage = globalThis.localStorage) {
  const normalised = normaliseFlowData(data);
  if (!storage || typeof storage.setItem !== 'function') return normalised;
  try {
    storage.setItem(FLOW_STORAGE_KEY, JSON.stringify(normalised));
  } catch {
    // Storage can be unavailable in private browsing. Gameplay remains usable.
  }
  return normalised;
}

export function recordFlowSession(data, result, storage = globalThis.localStorage) {
  const next = normaliseFlowData(data);
  const mode = result?.mode === 'endless' ? 'endless' : 'quick';
  const session = {
    mode,
    score: Math.max(0, Math.round(Number(result?.score) || 0)),
    flowScore: Math.max(0, Math.round(Number(result?.flowScore) || 0)),
    durationSeconds: Math.max(0, Math.round(Number(result?.durationSeconds) || 0)),
    smoothness: Math.max(0, Math.round(Number(result?.smoothness) || 0)),
    cleanApexRate: Math.max(0, Math.round(Number(result?.cleanApexRate) || 0)),
    streak: Math.max(0, Math.round(Number(result?.longestStreak) || 0)),
    createdAt: new Date().toISOString(),
  };
  next.sessions.push(session);
  next.sessions = next.sessions.slice(-FLOW_SESSION_LIMIT);
  const best = next.bests[mode];
  best.score = Math.max(best.score, session.score);
  best.flowScore = Math.max(best.flowScore, session.flowScore);
  best.streak = Math.max(best.streak, session.streak);
  if (mode === 'quick') {
    best.smoothness = Math.max(best.smoothness, session.smoothness);
    best.cleanApexRate = Math.max(best.cleanApexRate, session.cleanApexRate);
  } else {
    best.durationSeconds = Math.max(best.durationSeconds, session.durationSeconds);
  }
  return saveFlowData(next, storage);
}
