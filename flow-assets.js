export const FLOW_PALETTE = Object.freeze({
  black: '#020607',
  deepNavy: '#03131c',
  surface: '#071b23',
  raised: '#0b252c',
  cyan: '#22f5e2',
  cyanBright: '#7dfff4',
  blue: '#20b8ff',
  blueDeep: '#075ca8',
  magenta: '#ff3ebe',
  purple: '#6446d7',
  amber: '#e7a748',
  white: '#f1fbfa',
  muted: '#83999a',
});

export const QUALITY_PRESETS = Object.freeze({
  low: Object.freeze({ particles: 34, fogLayers: 1, bloom: false, reflections: false }),
  balanced: Object.freeze({ particles: 72, fogLayers: 2, bloom: true, reflections: true }),
  high: Object.freeze({ particles: 120, fogLayers: 3, bloom: true, reflections: true }),
});

export const SKY_PRESETS = Object.freeze({
  sunrise: Object.freeze({ top: '#160d20', bottom: '#4e2630', horizon: '#e7a748', mountain: '#151b29', fog: '#7b5061', particles: 'mist' }),
  day: Object.freeze({ top: '#082536', bottom: '#2b6678', horizon: '#7dfff4', mountain: '#0a2631', fog: '#6c9ba2', particles: 'fragments' }),
  goldenHour: Object.freeze({ top: '#180d23', bottom: '#713524', horizon: '#ffb45e', mountain: '#16121c', fog: '#87534c', particles: 'leaves' }),
  blueHour: Object.freeze({ top: '#041524', bottom: '#123e55', horizon: '#20b8ff', mountain: '#06131d', fog: '#305b70', particles: 'mist' }),
  night: Object.freeze({ top: '#010509', bottom: '#031924', horizon: '#22f5e2', mountain: '#02090d', fog: '#0d3d48', particles: 'fragments' }),
  storm: Object.freeze({ top: '#05080d', bottom: '#14202a', horizon: '#7dfff4', mountain: '#05080b', fog: '#39464c', particles: 'rain' }),
  aurora: Object.freeze({ top: '#02040b', bottom: '#071b25', horizon: '#22f5e2', mountain: '#03080c', fog: '#133f43', particles: 'fireflies' }),
});

export const MATERIAL_PRESETS = Object.freeze({
  dry: Object.freeze({ near: '#080f12', far: '#020608', grain: 0.08, reflectivity: 0.04 }),
  wet: Object.freeze({ near: '#050b0e', far: '#010405', grain: 0.04, reflectivity: 0.34 }),
  concrete: Object.freeze({ near: '#202a2d', far: '#0a1114', grain: 0.12, reflectivity: 0.08 }),
  tunnel: Object.freeze({ near: '#020405', far: '#000101', grain: 0.02, reflectivity: 0.24 }),
});

export const MOTORCYCLE_PRESETS = Object.freeze({
  sport: Object.freeze({ shoulder: 0.9, tail: 0.78, screen: 0.45, pannier: 0, stance: 0.84 }),
  adventure: Object.freeze({ shoulder: 0.88, tail: 0.7, screen: 0.82, pannier: 0.46, stance: 1 }),
  naked: Object.freeze({ shoulder: 0.76, tail: 0.62, screen: 0.18, pannier: 0, stance: 0.9 }),
  cruiser: Object.freeze({ shoulder: 1.06, tail: 0.92, screen: 0.28, pannier: 0.18, stance: 0.72 }),
  touring: Object.freeze({ shoulder: 1, tail: 0.82, screen: 0.9, pannier: 0.62, stance: 0.92 }),
  classic: Object.freeze({ shoulder: 0.82, tail: 0.72, screen: 0.2, pannier: 0, stance: 0.88 }),
});

export const ENVIRONMENT_PROPS = Object.freeze({
  reflector: Object.freeze({ spacing: 9, tint: FLOW_PALETTE.cyanBright }),
  beacon: Object.freeze({ spacing: 19, tint: FLOW_PALETTE.cyan }),
  pine: Object.freeze({ spacing: 27, tint: '#0a2624' }),
  guardRail: Object.freeze({ spacing: 4, tint: '#28464c' }),
  energyGate: Object.freeze({ spacing: 47, tint: FLOW_PALETTE.blue }),
  digitalSign: Object.freeze({ spacing: 41, tint: FLOW_PALETTE.magenta }),
});

export const PARTICLE_PRESETS = Object.freeze({
  streak: Object.freeze({ colour: FLOW_PALETTE.cyan, speed: 0.7, length: 8 }),
  dust: Object.freeze({ colour: '#6c7a76', speed: 0.18, length: 1 }),
  rain: Object.freeze({ colour: '#79cfff', speed: 1.8, length: 18 }),
  mist: Object.freeze({ colour: '#8bcbd0', speed: 0.06, length: 12 }),
  fireflies: Object.freeze({ colour: '#a4ff7a', speed: 0.08, length: 2 }),
  leaves: Object.freeze({ colour: FLOW_PALETTE.amber, speed: 0.24, length: 4 }),
  fragments: Object.freeze({ colour: FLOW_PALETTE.cyan, speed: 0.28, length: 6 }),
});

export function qualityPreset(name) {
  return QUALITY_PRESETS[name] || QUALITY_PRESETS.balanced;
}

export function motorcyclePreset(name) {
  return MOTORCYCLE_PRESETS[name] || MOTORCYCLE_PRESETS.sport;
}
