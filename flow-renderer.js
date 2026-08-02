import { sampleRoadAtDistance } from './flow-engine.js';
import {
  ENVIRONMENT_PROPS,
  FLOW_PALETTE,
  MATERIAL_PRESETS,
  SKY_PRESETS,
  motorcyclePreset,
  qualityPreset,
} from './flow-assets.js';
import { ParticlePool, createMountainLayers } from './flow-effects.js';

const TAU = Math.PI * 2;

function clamp(value, minimum = 0, maximum = 1) {
  return Math.max(minimum, Math.min(maximum, value));
}

function isLandscape(width, height) {
  return width > height && height < 620;
}

export class FlowRenderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.context = canvas.getContext('2d', { alpha: false, desynchronized: true });
    this.lightCanvas = document.createElement('canvas');
    this.lightContext = this.lightCanvas.getContext('2d', { alpha: true });
    this.projectedRoad = [];
    this.mountains = createMountainLayers('flow-idle-road');
    this.particles = new ParticlePool('flow-atmosphere');
    this.seed = 'flow-idle-road';
    this.width = 1;
    this.height = 1;
    this.dpr = 1;
    this.lastTimestamp = 0;
  }

  resize(width, height, dpr = 1) {
    const nextDpr = Math.min(2, Math.max(1, dpr));
    const pixelWidth = Math.max(1, Math.round(width * nextDpr));
    const pixelHeight = Math.max(1, Math.round(height * nextDpr));
    if (this.canvas.width !== pixelWidth || this.canvas.height !== pixelHeight) {
      this.canvas.width = pixelWidth;
      this.canvas.height = pixelHeight;
      this.lightCanvas.width = pixelWidth;
      this.lightCanvas.height = pixelHeight;
    }
    this.width = Math.max(1, width);
    this.height = Math.max(1, height);
    this.dpr = nextDpr;
    this.context.setTransform(nextDpr, 0, 0, nextDpr, 0, 0);
    this.lightContext.setTransform(nextDpr, 0, 0, nextDpr, 0, 0);
  }

  render(state, timestamp, settings = {}, appPhase = 'intro') {
    if (!this.width || !this.height) return;
    if (state.seed !== this.seed) {
      this.seed = state.seed;
      this.mountains = createMountainLayers(state.seed);
      this.particles = new ParticlePool(`${state.seed}-atmosphere`);
    }
    const reduced = Boolean(settings.reducedEffects);
    const quality = qualityPreset(reduced ? 'low' : settings.quality);
    const biome = this.resolveBiome(state, appPhase);
    const sky = SKY_PRESETS[biome];
    const material = this.resolveMaterial(state, biome);
    const breath = state.breathing?.enabled ? state.breathing.visualEnvelope : 0.5;
    const deltaTime = this.lastTimestamp ? (timestamp - this.lastTimestamp) / 1000 : 1 / 60;
    this.lastTimestamp = timestamp;

    this.clear(sky);
    this.drawStars(sky, timestamp, reduced);
    this.drawHorizon(sky, breath, reduced);
    this.drawMountains(sky, state, breath, reduced);
    const road = this.projectRoad(state, breath);
    this.drawRoadSurface(road, material);
    this.drawRoadTexture(road, material, state, timestamp);
    this.drawRoadEdges(road, state, settings);
    this.drawProps(road, state, biome, quality);
    this.drawHeadlight(road, state, quality);
    this.drawParticles(sky, quality, breath, deltaTime, reduced);
    this.drawMotorcycle(state, settings, material, timestamp);
    this.drawFog(sky, breath, quality, timestamp);
    if (quality.bloom) this.compositeBloom();
  }

  clear(sky) {
    const gradient = this.context.createLinearGradient(0, 0, 0, this.height);
    gradient.addColorStop(0, sky.top);
    gradient.addColorStop(0.52, sky.bottom);
    gradient.addColorStop(1, FLOW_PALETTE.black);
    this.context.fillStyle = gradient;
    this.context.fillRect(0, 0, this.width, this.height);
    this.lightContext.clearRect(0, 0, this.width, this.height);
  }

  resolveBiome(state, appPhase) {
    if (appPhase === 'results' || state.phase === 'land') return 'blueHour';
    if (state.mode !== 'endless') return 'night';
    const rotation = ['night', 'aurora', 'blueHour', 'storm'];
    return rotation[Math.floor(state.elapsed / 70) % rotation.length];
  }

  resolveMaterial(state, biome) {
    if (biome === 'storm') return MATERIAL_PRESETS.wet;
    if (state.mode === 'endless' && Math.floor(state.elapsed / 52) % 4 === 3) return MATERIAL_PRESETS.wet;
    return MATERIAL_PRESETS.dry;
  }

  horizonY() {
    return this.height * (isLandscape(this.width, this.height) ? 0.23 : 0.285);
  }

  drawStars(sky, timestamp, reduced) {
    if (!['#010509', '#02040b'].includes(sky.top)) return;
    this.context.save();
    for (let index = 0; index < (reduced ? 22 : 48); index += 1) {
      const x = ((index * 83.37) % 101) / 101 * this.width;
      const y = ((index * 47.91) % 67) / 67 * this.horizonY() * 0.82;
      const pulse = reduced ? 0.35 : 0.28 + Math.sin(timestamp * 0.001 + index) * 0.12;
      this.context.fillStyle = `rgba(183, 242, 245, ${pulse})`;
      this.context.fillRect(x, y, index % 7 === 0 ? 1.6 : 0.8, index % 7 === 0 ? 1.6 : 0.8);
    }
    this.context.restore();
  }

  drawHorizon(sky, breath, reduced) {
    const x = this.width / 2;
    const y = this.horizonY() - breath * (reduced ? 2 : 8);
    const radius = this.width * (0.38 + breath * 0.12);
    const glow = this.context.createRadialGradient(x, y, 0, x, y, radius);
    glow.addColorStop(0, `${sky.horizon}55`);
    glow.addColorStop(0.38, `${FLOW_PALETTE.blue}24`);
    glow.addColorStop(1, 'rgba(0,0,0,0)');
    this.context.fillStyle = glow;
    this.context.fillRect(0, 0, this.width, this.height * 0.66);

    this.context.save();
    this.context.strokeStyle = `${sky.horizon}74`;
    this.context.lineWidth = 1;
    this.context.shadowColor = sky.horizon;
    this.context.shadowBlur = 14;
    this.context.beginPath();
    this.context.arc(x, y + 12, radius * 0.34, Math.PI, TAU);
    this.context.stroke();
    this.context.restore();
  }

  drawMountains(sky, state, breath, reduced) {
    const horizon = this.horizonY();
    this.mountains.forEach((points, layer) => {
      const depth = layer / Math.max(1, this.mountains.length - 1);
      const parallax = reduced ? 0 : (state.road.travelled * (0.003 + layer * 0.002)) % this.width;
      const base = horizon + 72 - layer * 18;
      this.context.save();
      this.context.translate(-parallax * 0.08, 0);
      this.context.beginPath();
      points.forEach((point, index) => {
        const x = point.x * this.width * 1.12;
        const y = base - (0.82 - point.y) * this.height * (0.42 - layer * 0.045) - breath * (2 + layer * 2);
        if (index === 0) this.context.moveTo(x, y);
        else this.context.lineTo(x, y);
      });
      this.context.lineTo(this.width * 1.12, base + 90);
      this.context.lineTo(-this.width * 0.1, base + 90);
      this.context.closePath();
      this.context.fillStyle = layer === 0 ? `${sky.mountain}8f` : layer === 1 ? '#041014' : '#020708';
      this.context.fill();
      if (layer > 0) {
        this.context.strokeStyle = layer === 1 ? `${sky.horizon}44` : `${FLOW_PALETTE.cyan}2c`;
        this.context.lineWidth = 1;
        this.context.shadowColor = sky.horizon;
        this.context.shadowBlur = 8;
        this.context.stroke();
      }
      this.context.restore();
    });
  }

  projectRoad(state, breath) {
    this.projectedRoad.length = 0;
    const horizon = this.horizonY();
    const visibleHeight = this.height - horizon;
    const current = sampleRoadAtDistance(state, state.road.travelled);
    const lookAhead = isLandscape(this.width, this.height) ? 1500 : 1900;
    const count = 76;
    for (let index = 0; index <= count; index += 1) {
      const nearProgress = index / count;
      const distance = state.road.travelled + (1 - nearProgress) * lookAhead;
      const sample = sampleRoadAtDistance(state, distance);
      const perspective = Math.pow(nearProgress, 1.72);
      const y = horizon + perspective * visibleHeight * 1.1;
      const halfWidth = (2.5 + Math.pow(nearProgress, 1.34) * this.width * 0.5) * (1 + breath * 0.018);
      const scale = halfWidth / Math.max(1, sample.width);
      const center = this.width / 2 + (sample.centerX - current.centerX) * scale * Math.pow(nearProgress, 0.82);
      this.projectedRoad.push({
        x: center,
        y,
        halfWidth,
        targetX: center + (sample.targetX - sample.centerX) * scale,
        perspective,
        curvature: sample.curvature,
      });
    }
    return this.projectedRoad;
  }

  roadPath(road, xForPoint) {
    this.context.beginPath();
    road.forEach((point, index) => {
      const x = xForPoint(point);
      if (index === 0) this.context.moveTo(x, point.y);
      else this.context.lineTo(x, point.y);
    });
  }

  drawRoadSurface(road, material) {
    if (road.length < 2) return;
    this.context.beginPath();
    road.forEach((point, index) => {
      const x = point.x - point.halfWidth;
      if (index === 0) this.context.moveTo(x, point.y);
      else this.context.lineTo(x, point.y);
    });
    for (let index = road.length - 1; index >= 0; index -= 1) {
      const point = road[index];
      this.context.lineTo(point.x + point.halfWidth, point.y);
    }
    this.context.closePath();
    const roadGradient = this.context.createLinearGradient(0, this.horizonY(), 0, this.height);
    roadGradient.addColorStop(0, material.far);
    roadGradient.addColorStop(1, material.near);
    this.context.fillStyle = roadGradient;
    this.context.fill();

    const sheen = this.context.createLinearGradient(this.width * 0.25, 0, this.width * 0.75, 0);
    sheen.addColorStop(0, 'rgba(255,255,255,0)');
    sheen.addColorStop(0.5, `rgba(125,255,244,${material.reflectivity * 0.2})`);
    sheen.addColorStop(1, 'rgba(255,255,255,0)');
    this.context.fillStyle = sheen;
    this.context.fill();
  }

  drawRoadTexture(road, material, state, timestamp) {
    this.context.save();
    this.context.lineCap = 'round';
    const dashOffset = Math.floor(timestamp / 85) % 9;
    for (let index = 6 + dashOffset; index < road.length - 2; index += 10) {
      const far = road[index];
      const near = road[Math.min(road.length - 1, index + 4)];
      this.context.strokeStyle = `rgba(143, 188, 190, ${0.08 + near.perspective * 0.16})`;
      this.context.lineWidth = 0.7 + near.perspective * 2.1;
      this.context.beginPath();
      this.context.moveTo(far.x, far.y);
      this.context.lineTo(near.x, near.y);
      this.context.stroke();
    }

    for (let lane = -2; lane <= 2; lane += 1) {
      const ratio = lane * 0.13;
      this.roadPath(road, point => point.x + point.halfWidth * ratio);
      this.context.strokeStyle = `rgba(177, 209, 207, ${material.grain * (lane === 0 ? 0.7 : 0.35)})`;
      this.context.lineWidth = 0.6;
      this.context.stroke();
    }
    this.context.restore();

    if (material.reflectivity > 0.2) {
      const reflection = this.context.createLinearGradient(0, this.horizonY(), 0, this.height);
      reflection.addColorStop(0, 'rgba(34,245,226,0)');
      reflection.addColorStop(0.65, `rgba(34,245,226,${material.reflectivity * 0.09})`);
      reflection.addColorStop(1, 'rgba(32,184,255,0.02)');
      this.context.fillStyle = reflection;
      this.context.fillRect(0, this.horizonY(), this.width, this.height - this.horizonY());
    }
  }

  drawRoadEdges(road, state, settings) {
    const chain = state.metrics.currentStreak >= 3;
    const left = chain ? FLOW_PALETTE.magenta : FLOW_PALETTE.cyan;
    const passes = [
      { width: 15, alpha: 0.08 },
      { width: 7, alpha: 0.2 },
      { width: 2, alpha: 0.92 },
    ];
    for (const pass of passes) {
      this.context.save();
      this.context.lineJoin = 'round';
      this.context.lineCap = 'round';
      this.roadPath(road, point => point.x - point.halfWidth);
      this.context.strokeStyle = `${left}${Math.round(pass.alpha * 255).toString(16).padStart(2, '0')}`;
      this.context.lineWidth = pass.width;
      this.context.stroke();
      this.roadPath(road, point => point.x + point.halfWidth);
      this.context.strokeStyle = `${FLOW_PALETTE.blue}${Math.round(pass.alpha * 255).toString(16).padStart(2, '0')}`;
      this.context.stroke();
      this.context.restore();
    }

    if (settings.lineGuide !== 'off') {
      const opacity = settings.lineGuide === 'full' ? 0.54 : 0.16;
      this.context.save();
      this.roadPath(road, point => point.targetX);
      this.context.strokeStyle = chain ? `${FLOW_PALETTE.magenta}9c` : `rgba(125,255,244,${opacity})`;
      this.context.lineWidth = settings.lineGuide === 'full' ? 3.2 : 1.4;
      this.context.shadowColor = chain ? FLOW_PALETTE.magenta : FLOW_PALETTE.cyan;
      this.context.shadowBlur = settings.lineGuide === 'full' ? 13 : 6;
      this.context.stroke();
      this.context.restore();
    }
  }

  drawProps(road, state, biome, quality) {
    this.context.save();
    for (let index = 8; index < road.length - 3; index += ENVIRONMENT_PROPS.reflector.spacing) {
      const point = road[index];
      const size = 1 + point.perspective * 3;
      this.context.fillStyle = 'rgba(241,251,250,0.78)';
      for (const side of [-1, 1]) {
        const x = point.x + side * point.halfWidth * 1.05;
        this.context.beginPath();
        this.context.arc(x, point.y, size, 0, TAU);
        this.context.fill();
      }
    }

    for (let index = 18; index < road.length - 8; index += ENVIRONMENT_PROPS.beacon.spacing) {
      const point = road[index];
      const side = index % 38 === 0 ? -1 : 1;
      const height = 3 + point.perspective * 24;
      const x = point.x + side * point.halfWidth * 1.23;
      this.context.strokeStyle = index % 3 === 0 ? `${FLOW_PALETTE.magenta}88` : `${FLOW_PALETTE.cyan}88`;
      this.context.lineWidth = 1 + point.perspective * 2;
      this.context.beginPath();
      this.context.moveTo(x, point.y);
      this.context.lineTo(x, point.y - height);
      this.context.stroke();
    }

    if (quality.reflections && biome !== 'storm') {
      for (let index = 24; index < road.length - 12; index += ENVIRONMENT_PROPS.pine.spacing) {
        const point = road[index];
        const side = index % 54 === 0 ? -1 : 1;
        this.drawPine(point.x + side * point.halfWidth * 1.42, point.y, point.perspective);
      }
    }

    if (road.length > 58) {
      this.drawGuardRail(road.slice(38, 58), state.road.travelled);
    }
    if (road.length > 46) {
      this.drawDigitalSign(road[42], state.metrics.currentStreak);
    }
    if (quality.bloom && road.length > 30) {
      this.drawEnergyGate(road[26], state.breathing.phaseProgress);
    }
    this.context.restore();
  }

  drawPine(x, y, perspective) {
    const height = 4 + perspective * 44;
    const width = 2 + perspective * 15;
    this.context.fillStyle = 'rgba(3,22,20,0.86)';
    this.context.beginPath();
    this.context.moveTo(x, y - height);
    this.context.lineTo(x - width, y);
    this.context.lineTo(x + width, y);
    this.context.closePath();
    this.context.fill();
    this.context.strokeStyle = 'rgba(34,245,226,0.16)';
    this.context.stroke();
  }

  drawGuardRail(points, travelled) {
    if (points.length < 2 || Math.floor(travelled / 1800) % 3 === 1) return;
    const side = Math.floor(travelled / 900) % 2 === 0 ? -1 : 1;
    this.context.save();
    this.context.lineJoin = 'round';
    this.context.lineCap = 'round';
    this.context.beginPath();
    points.forEach((point, index) => {
      const x = point.x + side * point.halfWidth * 1.14;
      if (index === 0) this.context.moveTo(x, point.y);
      else this.context.lineTo(x, point.y);
    });
    this.context.strokeStyle = 'rgba(40,70,76,0.72)';
    this.context.lineWidth = 2.2;
    this.context.stroke();
    this.context.strokeStyle = 'rgba(125,255,244,0.2)';
    this.context.lineWidth = 0.8;
    this.context.stroke();
    this.context.restore();
  }

  drawDigitalSign(point, streak) {
    if (!point || point.perspective < 0.16) return;
    const side = streak % 2 === 0 ? 1 : -1;
    const width = 8 + point.perspective * 30;
    const height = width * 0.48;
    const x = point.x + side * point.halfWidth * 1.4;
    const y = point.y - height * 1.4;
    this.context.save();
    this.context.fillStyle = 'rgba(2,8,11,0.88)';
    this.context.strokeStyle = 'rgba(255,62,190,0.48)';
    this.context.lineWidth = 1;
    this.context.fillRect(x - width / 2, y - height / 2, width, height);
    this.context.strokeRect(x - width / 2, y - height / 2, width, height);
    this.context.fillStyle = streak >= 3 ? FLOW_PALETTE.magenta : FLOW_PALETTE.cyan;
    this.context.fillRect(x - width * 0.3, y - 0.7, width * 0.6, 1.4);
    this.context.strokeStyle = 'rgba(40,70,76,0.78)';
    this.context.beginPath();
    this.context.moveTo(x, y + height / 2);
    this.context.lineTo(x, point.y);
    this.context.stroke();
    this.context.restore();
  }

  drawEnergyGate(point, phaseProgress) {
    if (!point || point.perspective < 0.1) return;
    const width = point.halfWidth * 2.08;
    const height = 9 + point.perspective * 68;
    const brightness = 0.1 + phaseProgress * 0.12;
    this.context.save();
    this.context.strokeStyle = `rgba(32,184,255,${brightness})`;
    this.context.lineWidth = 1 + point.perspective * 2;
    this.context.beginPath();
    this.context.moveTo(point.x - width / 2, point.y);
    this.context.lineTo(point.x - width / 2, point.y - height * 0.54);
    this.context.quadraticCurveTo(point.x, point.y - height, point.x + width / 2, point.y - height * 0.54);
    this.context.lineTo(point.x + width / 2, point.y);
    this.context.stroke();
    this.context.restore();
  }

  drawHeadlight(road, state, quality) {
    if (!quality.bloom || road.length < 20) return;
    const near = road[road.length - 1];
    const far = road[Math.max(0, road.length - 30)];
    const beam = this.lightContext.createLinearGradient(0, near.y, 0, far.y);
    beam.addColorStop(0, 'rgba(125,255,244,0.18)');
    beam.addColorStop(1, 'rgba(125,255,244,0)');
    this.lightContext.fillStyle = beam;
    this.lightContext.beginPath();
    this.lightContext.moveTo(near.x - near.halfWidth * 0.17, near.y);
    this.lightContext.lineTo(far.x - far.halfWidth * 0.8, far.y);
    this.lightContext.lineTo(far.x + far.halfWidth * 0.8, far.y);
    this.lightContext.lineTo(near.x + near.halfWidth * 0.17, near.y);
    this.lightContext.closePath();
    this.lightContext.fill();
  }

  drawParticles(sky, quality, breath, deltaTime, reduced) {
    this.particles.configure({
      count: reduced ? Math.min(quality.particles, 28) : quality.particles,
      type: sky.particles,
      width: this.width,
      height: this.height,
    });
    this.particles.update(deltaTime, breath);
    this.context.save();
    this.context.lineCap = 'round';
    this.particles.forEach(particle => {
      this.context.globalAlpha = particle.opacity;
      this.context.strokeStyle = particle.colour;
      this.context.fillStyle = particle.colour;
      if (particle.type === 'fireflies' || particle.type === 'mist') {
        this.context.beginPath();
        this.context.arc(particle.x, particle.y, particle.size * (particle.type === 'mist' ? 3 : 1), 0, TAU);
        this.context.fill();
      } else {
        this.context.lineWidth = particle.size;
        this.context.beginPath();
        this.context.moveTo(particle.x, particle.y);
        this.context.lineTo(particle.x + particle.velocityX * 0.06, particle.y + particle.length * particle.z);
        this.context.stroke();
      }
    });
    this.context.restore();
  }

  drawMotorcycle(state, settings, material, timestamp) {
    const road = sampleRoadAtDistance(state, state.road.travelled);
    const nearHalfWidth = this.width * 0.5;
    const scale = nearHalfWidth / Math.max(1, road.width);
    const x = this.width / 2 + (state.bike.x - road.centerX) * scale;
    const y = this.height * (isLandscape(this.width, this.height) ? 0.8 : 0.81);
    const bike = motorcyclePreset(settings.motorcycle);
    const flow = clamp(state.metrics.flow / 100);
    const lean = settings.reducedEffects ? 0 : state.bike.lean * 0.18;
    const correction = clamp(Math.abs(state.input?.jerk || 0) / 20);
    const baseScale = clamp(this.width / 390, 0.82, 1.26) * bike.stance;

    this.context.save();
    this.context.translate(x, y);
    this.context.rotate(lean);
    this.context.scale(baseScale, baseScale);
    const shadow = this.context.createRadialGradient(0, 23, 2, 0, 23, 42);
    shadow.addColorStop(0, 'rgba(0,0,0,0.66)');
    shadow.addColorStop(1, 'rgba(0,0,0,0)');
    this.context.fillStyle = shadow;
    this.context.fillRect(-48, 4, 96, 52);

    if (material.reflectivity > 0.2) {
      this.context.save();
      this.context.globalAlpha = 0.16;
      this.context.scale(1, -0.82);
      this.context.translate(0, -55);
      this.drawBikeBody(bike, flow, correction);
      this.context.restore();
    }
    this.drawBikeBody(bike, flow, correction);

    const underglow = this.context.createRadialGradient(0, 24, 0, 0, 24, 42);
    underglow.addColorStop(0, `rgba(34,245,226,${0.18 + flow * 0.2})`);
    underglow.addColorStop(1, 'rgba(34,245,226,0)');
    this.context.fillStyle = underglow;
    this.context.beginPath();
    this.context.ellipse(0, 24, 42, 16, 0, 0, TAU);
    this.context.fill();

    const pulse = 0.7 + Math.sin(timestamp * 0.004) * 0.16;
    this.context.strokeStyle = state.metrics.currentStreak >= 3 ? FLOW_PALETTE.magenta : FLOW_PALETTE.cyan;
    this.context.globalAlpha = pulse;
    this.context.lineWidth = 2;
    this.context.beginPath();
    this.context.moveTo(-17, 31);
    this.context.lineTo(-20, 52);
    this.context.moveTo(17, 31);
    this.context.lineTo(20, 52);
    this.context.stroke();
    this.context.restore();
  }

  drawBikeBody(bike, flow, correction) {
    const shoulder = 25 * bike.shoulder;
    const tail = 16 * bike.tail;
    this.context.fillStyle = '#030708';
    this.context.strokeStyle = 'rgba(125,255,244,0.64)';
    this.context.lineWidth = 1.4;

    this.context.beginPath();
    this.context.ellipse(-shoulder, 18, 7, 14, -0.08, 0, TAU);
    this.context.ellipse(shoulder, 18, 7, 14, 0.08, 0, TAU);
    this.context.fill();
    this.context.stroke();

    if (bike.pannier > 0) {
      this.context.fillRect(-shoulder - 9, 6, 12 * bike.pannier, 17);
      this.context.fillRect(shoulder - 3, 6, 12 * bike.pannier, 17);
    }

    this.context.beginPath();
    this.context.moveTo(0, -31 - bike.screen * 5);
    this.context.quadraticCurveTo(shoulder * 0.75, -11, tail, 30);
    this.context.lineTo(-tail, 30);
    this.context.quadraticCurveTo(-shoulder * 0.75, -11, 0, -31 - bike.screen * 5);
    this.context.closePath();
    this.context.fill();
    this.context.stroke();

    this.context.fillStyle = '#09161a';
    this.context.beginPath();
    this.context.arc(0, -10, 12, 0, TAU);
    this.context.fill();
    this.context.stroke();

    this.context.fillStyle = correction > 0.55 ? FLOW_PALETTE.magenta : FLOW_PALETTE.cyan;
    this.context.shadowColor = this.context.fillStyle;
    this.context.shadowBlur = 9 + flow * 8;
    this.context.fillRect(-9, 23, 18, 4.5);
    this.context.fillStyle = FLOW_PALETTE.white;
    this.context.beginPath();
    this.context.arc(0, -14, 4.4, 0, TAU);
    this.context.fill();
    this.context.shadowBlur = 0;
  }

  drawFog(sky, breath, quality, timestamp) {
    this.context.save();
    for (let layer = 0; layer < quality.fogLayers; layer += 1) {
      const y = this.horizonY() + this.height * (0.08 + layer * 0.14);
      const drift = Math.sin(timestamp * 0.00008 + layer) * this.width * 0.08;
      const fog = this.context.createRadialGradient(this.width * 0.5 + drift, y, 0, this.width * 0.5 + drift, y, this.width * 0.72);
      fog.addColorStop(0, `${sky.fog}${Math.round((0.05 + breath * 0.035) * 255).toString(16).padStart(2, '0')}`);
      fog.addColorStop(1, 'rgba(0,0,0,0)');
      this.context.fillStyle = fog;
      this.context.fillRect(0, y - this.height * 0.12, this.width, this.height * 0.38);
    }
    this.context.restore();
  }

  compositeBloom() {
    this.context.save();
    this.context.globalCompositeOperation = 'lighter';
    this.context.filter = 'blur(8px)';
    this.context.globalAlpha = 0.72;
    this.context.drawImage(this.lightCanvas, 0, 0, this.width, this.height);
    this.context.filter = 'none';
    this.context.globalAlpha = 1;
    this.context.drawImage(this.lightCanvas, 0, 0, this.width, this.height);
    this.context.restore();
  }
}
