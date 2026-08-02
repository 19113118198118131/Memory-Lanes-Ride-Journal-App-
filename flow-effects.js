import { PARTICLE_PRESETS } from './flow-assets.js';

function hashSeed(seed) {
  let value = 2166136261;
  for (const character of String(seed)) {
    value ^= character.charCodeAt(0);
    value = Math.imul(value, 16777619);
  }
  return value >>> 0;
}

export function createVisualRandom(seed) {
  let value = hashSeed(seed) || 1;
  return () => {
    value += 0x6d2b79f5;
    let result = value;
    result = Math.imul(result ^ (result >>> 15), result | 1);
    result ^= result + Math.imul(result ^ (result >>> 7), result | 61);
    return ((result ^ (result >>> 14)) >>> 0) / 4294967296;
  };
}

export function createMountainLayers(seed, layerCount = 3, pointCount = 14) {
  const random = createVisualRandom(`${seed}-mountains`);
  return Array.from({ length: layerCount }, (_, layer) => {
    const points = [{ x: -0.08, y: 0.78 - layer * 0.04 }];
    for (let index = 0; index < pointCount; index += 1) {
      const progress = index / Math.max(1, pointCount - 1);
      const ridge = 0.42 + layer * 0.06 + random() * (0.22 - layer * 0.035);
      points.push({ x: progress * 1.16 - 0.08, y: ridge });
    }
    points.push({ x: 1.08, y: 0.82 });
    return points;
  });
}

function resetParticle(particle, random, width, height, type, fromBottom = false) {
  const preset = PARTICLE_PRESETS[type] || PARTICLE_PRESETS.fragments;
  particle.type = type;
  particle.x = random() * width;
  particle.y = fromBottom ? height + random() * 40 : random() * height;
  particle.z = 0.2 + random() * 0.8;
  particle.velocityX = (random() - 0.5) * 12 * particle.z;
  particle.velocityY = -(12 + random() * 36) * preset.speed;
  particle.size = 0.7 + random() * 1.9;
  particle.opacity = 0.12 + random() * 0.38;
  particle.life = 2 + random() * 6;
  particle.rotation = random() * Math.PI * 2;
  particle.colour = preset.colour;
  particle.length = preset.length;
}

export class ParticlePool {
  constructor(seed = 'flow-particles', capacity = 120) {
    this.random = createVisualRandom(seed);
    this.pool = Array.from({ length: capacity }, () => ({}));
    this.activeCount = 0;
    this.type = 'fragments';
    this.width = 1;
    this.height = 1;
  }

  configure({ count, type, width, height }) {
    this.activeCount = Math.min(this.pool.length, Math.max(0, count));
    this.type = PARTICLE_PRESETS[type] ? type : 'fragments';
    this.width = Math.max(1, width);
    this.height = Math.max(1, height);
    for (let index = 0; index < this.activeCount; index += 1) {
      const particle = this.pool[index];
      if (!Number.isFinite(particle.life) || particle.type !== this.type) {
        resetParticle(particle, this.random, this.width, this.height, this.type);
      }
    }
  }

  update(deltaTime, breathEnvelope = 0.5) {
    const dt = Math.min(0.05, Math.max(0, deltaTime));
    for (let index = 0; index < this.activeCount; index += 1) {
      const particle = this.pool[index];
      particle.x += particle.velocityX * dt * (0.8 + breathEnvelope * 0.4);
      particle.y += particle.velocityY * dt * (0.72 + breathEnvelope * 0.5);
      particle.life -= dt;
      particle.rotation += dt * particle.z;
      if (particle.life <= 0 || particle.y < -30 || particle.x < -40 || particle.x > this.width + 40) {
        resetParticle(particle, this.random, this.width, this.height, this.type, true);
      }
    }
  }

  forEach(callback) {
    for (let index = 0; index < this.activeCount; index += 1) callback(this.pool[index], index);
  }
}

export function breathingEnvelope(progress) {
  const bounded = Math.max(0, Math.min(1, progress));
  return 0.5 - 0.5 * Math.cos(bounded * Math.PI);
}
