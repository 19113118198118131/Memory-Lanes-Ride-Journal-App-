import * as pc from './vendor/playcanvas/playcanvas.min.mjs';
import { sampleRoadAtDistance } from './flow-engine.js';
import { FLOW_PALETTE, SKY_PRESETS, motorcyclePreset, qualityPreset } from './flow-assets.js';

const ROAD_SEGMENTS = 64;
const ROAD_LOOK_AHEAD = 1850;
const ROAD_HALF_WIDTH = 4.7;
const WORLD_DEPTH = 132;

function clamp(value, minimum = 0, maximum = 1) {
  return Math.max(minimum, Math.min(maximum, value));
}

function hexColour(hex) {
  const value = hex.replace('#', '');
  return new pc.Color(
    parseInt(value.slice(0, 2), 16) / 255,
    parseInt(value.slice(2, 4), 16) / 255,
    parseInt(value.slice(4, 6), 16) / 255,
  );
}

function makeMaterial({ colour, emissive, emissiveIntensity = 0, metalness = 0, gloss = 0.5, opacity = 1 }) {
  const material = new pc.StandardMaterial();
  material.diffuse = hexColour(colour);
  material.metalness = metalness;
  material.gloss = gloss;
  if (emissive) {
    material.emissive = hexColour(emissive);
    material.emissiveIntensity = emissiveIntensity;
  }
  if (opacity < 1) {
    material.opacity = opacity;
    material.blendType = pc.BLEND_NORMAL;
    material.depthWrite = false;
  }
  material.update();
  return material;
}

function primitive(app, name, type, material, parent, castShadows = false) {
  const entity = new pc.Entity(name);
  entity.addComponent('render', { type, material, castShadows, receiveShadows: true });
  (parent || app.root).addChild(entity);
  return entity;
}

function setTransform(entity, position, scale, euler = [0, 0, 0]) {
  entity.setLocalPosition(position[0], position[1], position[2]);
  entity.setLocalScale(scale[0], scale[1], scale[2]);
  entity.setLocalEulerAngles(euler[0], euler[1], euler[2]);
}

export class FlowPlayCanvasRenderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.width = 1;
    this.height = 1;
    this.dpr = 1;
    this.lastTimestamp = 0;
    this.cameraX = 0;
    this.cameraLookX = 0;
    this.seed = '';
    this.currentBiome = '';
    this.app = new pc.Application(canvas, {
      graphicsDeviceOptions: {
        alpha: false,
        antialias: true,
        powerPreference: 'high-performance',
      },
    });
    this.app.setCanvasFillMode(pc.FILLMODE_NONE);
    this.app.setCanvasResolution(pc.RESOLUTION_AUTO);
    this.app.autoRender = false;
    this.createMaterials();
    this.createScene();
    this.app.start();
  }

  createMaterials() {
    this.materials = {
      road: makeMaterial({ colour: '#071014', metalness: 0.22, gloss: 0.78 }),
      roadWet: makeMaterial({ colour: '#02080b', metalness: 0.52, gloss: 0.96 }),
      roadShoulder: makeMaterial({ colour: '#03080a', metalness: 0.18, gloss: 0.62 }),
      cyan: makeMaterial({ colour: '#092827', emissive: FLOW_PALETTE.cyan, emissiveIntensity: 4.2, gloss: 0.86 }),
      blue: makeMaterial({ colour: '#071e2d', emissive: FLOW_PALETTE.blue, emissiveIntensity: 3.6, gloss: 0.84 }),
      magenta: makeMaterial({ colour: '#2b0922', emissive: FLOW_PALETTE.magenta, emissiveIntensity: 2.8, gloss: 0.8 }),
      marker: makeMaterial({ colour: '#8ffcf4', emissive: '#7dfff4', emissiveIntensity: 1.7, gloss: 0.9 }),
      bike: makeMaterial({ colour: '#05090b', metalness: 0.88, gloss: 0.88 }),
      bikeTrim: makeMaterial({ colour: '#0b2b2e', metalness: 0.68, gloss: 0.92 }),
      rubber: makeMaterial({ colour: '#010202', metalness: 0.02, gloss: 0.18 }),
      ground: makeMaterial({ colour: '#020607', metalness: 0.04, gloss: 0.22 }),
      mountain: makeMaterial({ colour: '#031016', metalness: 0.02, gloss: 0.1 }),
      mountainNear: makeMaterial({ colour: '#010507', metalness: 0.02, gloss: 0.08 }),
      beacon: makeMaterial({ colour: '#07161a', emissive: '#20b8ff', emissiveIntensity: 2.3, gloss: 0.72 }),
    };
  }

  createScene() {
    const { app } = this;
    app.scene.ambientLight = new pc.Color(0.025, 0.075, 0.09);
    app.scene.fog.type = pc.FOG_EXP2;
    app.scene.fog.color = new pc.Color(0.008, 0.035, 0.052);
    app.scene.fog.density = 0.018;

    this.camera = new pc.Entity('Flow chase camera');
    this.camera.addComponent('camera', {
      clearColor: new pc.Color(0.004, 0.015, 0.024),
      fov: 59,
      nearClip: 0.08,
      farClip: 220,
      toneMapping: pc.TONEMAP_ACES,
    });
    app.root.addChild(this.camera);

    const moon = new pc.Entity('Moon light');
    moon.addComponent('light', {
      type: 'directional',
      color: new pc.Color(0.18, 0.42, 0.62),
      intensity: 1.35,
      castShadows: true,
      shadowDistance: 75,
      shadowResolution: 1024,
      normalOffsetBias: 0.05,
    });
    moon.setEulerAngles(48, 28, 18);
    app.root.addChild(moon);
    this.moon = moon;

    this.horizonLight = new pc.Entity('Breathing horizon');
    this.horizonLight.addComponent('light', {
      type: 'point',
      color: hexColour(FLOW_PALETTE.cyan),
      intensity: 4.5,
      range: 80,
      castShadows: false,
    });
    this.horizonLight.setPosition(0, 8, -78);
    app.root.addChild(this.horizonLight);

    this.bikeLight = new pc.Entity('Bike headlight');
    this.bikeLight.addComponent('light', {
      type: 'spot',
      color: new pc.Color(0.45, 0.95, 1),
      intensity: 3.3,
      range: 42,
      innerConeAngle: 22,
      outerConeAngle: 38,
      castShadows: false,
    });
    app.root.addChild(this.bikeLight);

    this.ground = primitive(app, 'Digital landscape', 'box', this.materials.ground);
    setTransform(this.ground, [0, -0.42, -58], [180, 0.5, 160]);

    this.createRoad();
    this.createMotorcycle();
    this.createMountains();
    this.createRoadsideWorld();
    this.camera.setPosition(0, 4.5, 10.8);
    this.camera.lookAt(0, 0.45, -19);
  }

  createRoad() {
    this.roadRoot = new pc.Entity('Procedural road');
    this.app.root.addChild(this.roadRoot);
    this.roadPieces = [];
    for (let index = 0; index < ROAD_SEGMENTS; index += 1) {
      const road = primitive(this.app, `Road ${index}`, 'box', this.materials.road, this.roadRoot);
      const shoulder = primitive(this.app, `Shoulder ${index}`, 'box', this.materials.roadShoulder, this.roadRoot);
      const left = primitive(this.app, `Left light ${index}`, 'box', this.materials.cyan, this.roadRoot);
      const right = primitive(this.app, `Right light ${index}`, 'box', this.materials.blue, this.roadRoot);
      const marker = primitive(this.app, `Guide ${index}`, 'box', this.materials.marker, this.roadRoot);
      this.roadPieces.push({ road, shoulder, left, right, marker });
    }
  }

  createMotorcycle() {
    this.bikeRoot = new pc.Entity('Model-ready motorcycle anchor');
    this.app.root.addChild(this.bikeRoot);

    const body = primitive(this.app, 'Motorcycle body', 'capsule', this.materials.bike, this.bikeRoot, true);
    setTransform(body, [0, 0.67, 0], [0.72, 0.58, 1.5], [90, 0, 0]);
    const tank = primitive(this.app, 'Motorcycle tank', 'sphere', this.materials.bikeTrim, this.bikeRoot, true);
    setTransform(tank, [0, 0.98, -0.12], [0.76, 0.48, 0.92]);
    const tail = primitive(this.app, 'Motorcycle tail', 'box', this.materials.bike, this.bikeRoot, true);
    setTransform(tail, [0, 0.82, 0.78], [0.58, 0.2, 0.7], [-8, 0, 0]);
    const rider = primitive(this.app, 'Rider', 'capsule', this.materials.bike, this.bikeRoot, true);
    setTransform(rider, [0, 1.48, 0.08], [0.52, 0.8, 0.52], [12, 0, 0]);
    const helmet = primitive(this.app, 'Rider helmet', 'sphere', this.materials.bikeTrim, this.bikeRoot, true);
    setTransform(helmet, [0, 2.05, -0.16], [0.48, 0.48, 0.48]);

    [-0.82, 0.9].forEach((z, index) => {
      const wheel = primitive(this.app, index ? 'Rear wheel' : 'Front wheel', 'cylinder', this.materials.rubber, this.bikeRoot, true);
      setTransform(wheel, [0, 0.45, z], [0.72, 0.18, 0.72], [0, 0, 90]);
      const rim = primitive(this.app, index ? 'Rear luminous rim' : 'Front luminous rim', 'cylinder', this.materials.cyan, this.bikeRoot);
      setTransform(rim, [0, 0.45, z], [0.49, 0.19, 0.49], [0, 0, 90]);
    });

    this.tailLight = primitive(this.app, 'Tail light', 'box', this.materials.magenta, this.bikeRoot);
    setTransform(this.tailLight, [0, 0.9, 1.18], [0.42, 0.09, 0.08]);
    this.underglow = primitive(this.app, 'Bike underglow', 'sphere', this.materials.cyan, this.bikeRoot);
    setTransform(this.underglow, [0, 0.18, 0.25], [1.15, 0.035, 1.8]);
  }

  createMountains() {
    this.mountainRoot = new pc.Entity('Layered mountains');
    this.app.root.addChild(this.mountainRoot);
    const ridges = [
      { depth: -86, scale: 18, height: 16, material: this.materials.mountain },
      { depth: -104, scale: 24, height: 22, material: this.materials.mountainNear },
      { depth: -126, scale: 31, height: 28, material: this.materials.mountain },
    ];
    ridges.forEach((ridge, layer) => {
      for (let index = -4; index <= 4; index += 1) {
        const peak = primitive(this.app, `Ridge ${layer}-${index}`, 'cone', ridge.material, this.mountainRoot);
        const variance = 0.72 + ((index * index + layer * 7) % 5) * 0.11;
        setTransform(
          peak,
          [index * ridge.scale * 0.78 + (layer % 2) * 5, ridge.height * variance * 0.48 - 1, ridge.depth],
          [ridge.scale * variance, ridge.height * variance, ridge.scale * 0.62],
        );
      }
    });
  }

  createRoadsideWorld() {
    this.propRoot = new pc.Entity('Roadside world');
    this.app.root.addChild(this.propRoot);
    this.beacons = [];
    for (let index = 0; index < 26; index += 1) {
      const side = index % 2 ? 1 : -1;
      const beacon = primitive(this.app, `Road beacon ${index}`, 'cylinder', this.materials.beacon, this.propRoot);
      setTransform(beacon, [side * (8 + (index % 3) * 2.4), 1.05, -index * 5.2], [0.09, 2.1, 0.09]);
      this.beacons.push({ entity: beacon, side, index });
    }
  }

  resize(width, height, dpr = 1) {
    this.width = Math.max(1, width);
    this.height = Math.max(1, height);
    this.dpr = Math.min(2, Math.max(1, dpr));
    this.app.graphicsDevice.maxPixelRatio = this.dpr;
    this.app.resizeCanvas(this.width, this.height);
    this.camera.camera.fov = width > height ? 50 : 59;
  }

  resolveBiome(state, appPhase) {
    if (appPhase === 'results' || state.phase === 'land') return 'blueHour';
    if (state.mode !== 'endless') return 'night';
    return ['night', 'aurora', 'blueHour', 'storm'][Math.floor(state.elapsed / 70) % 4];
  }

  applyBiome(name, breath) {
    if (name !== this.currentBiome) this.currentBiome = name;
    const sky = SKY_PRESETS[name] || SKY_PRESETS.night;
    const top = hexColour(sky.top);
    this.camera.camera.clearColor = top;
    this.app.scene.fog.color = hexColour(sky.bottom);
    this.moon.light.color = hexColour(sky.horizon);
    this.horizonLight.light.color = hexColour(sky.horizon);
    this.horizonLight.light.intensity = 3.4 + breath * 4.1;
    this.app.scene.ambientLight = new pc.Color(
      0.025 + breath * 0.012,
      0.065 + breath * 0.025,
      0.082 + breath * 0.035,
    );
  }

  updateRoad(state, biome) {
    const current = sampleRoadAtDistance(state, state.road.travelled);
    const wet = biome === 'storm' || (state.mode === 'endless' && Math.floor(state.elapsed / 52) % 4 === 3);
    this.roadPieces.forEach((piece, index) => {
      const t = index / (ROAD_SEGMENTS - 1);
      const distance = state.road.travelled + t * ROAD_LOOK_AHEAD;
      const nextDistance = state.road.travelled + Math.min(1, t + 1 / (ROAD_SEGMENTS - 1)) * ROAD_LOOK_AHEAD;
      const sample = sampleRoadAtDistance(state, distance);
      const next = sampleRoadAtDistance(state, nextDistance);
      const x = clamp((sample.centerX - current.centerX) / 34, -26, 26);
      const nextX = clamp((next.centerX - current.centerX) / 34, -26, 26);
      const z = 3.2 - t * WORLD_DEPTH;
      const nextZ = 3.2 - Math.min(1, t + 1 / (ROAD_SEGMENTS - 1)) * WORLD_DEPTH;
      const dx = nextX - x;
      const dz = nextZ - z;
      const length = Math.hypot(dx, dz) + 0.34;
      const yaw = Math.atan2(-dx, -dz) * 180 / Math.PI;
      const roadScale = 0.9 + clamp(sample.width / 205, 0.78, 1.08) * 0.1;
      const halfWidth = ROAD_HALF_WIDTH * roadScale;
      const centerX = (x + nextX) * 0.5;
      const centerZ = (z + nextZ) * 0.5;
      piece.road.render.material = wet ? this.materials.roadWet : this.materials.road;
      setTransform(piece.shoulder, [centerX, -0.13, centerZ], [halfWidth * 2.25, 0.12, length], [0, yaw, 0]);
      setTransform(piece.road, [centerX, 0, centerZ], [halfWidth * 2, 0.14, length], [0, yaw, 0]);

      const sideX = Math.cos(yaw * Math.PI / 180) * halfWidth;
      const sideZ = -Math.sin(yaw * Math.PI / 180) * halfWidth;
      setTransform(piece.left, [centerX - sideX, 0.13, centerZ - sideZ], [0.085, 0.045, length], [0, yaw, 0]);
      setTransform(piece.right, [centerX + sideX, 0.13, centerZ + sideZ], [0.085, 0.045, length], [0, yaw, 0]);

      const guideOffset = ((sample.targetX - sample.centerX) / Math.max(1, sample.width)) * halfWidth;
      const showMarker = index % 4 < 2;
      piece.marker.enabled = showMarker;
      if (showMarker) {
        setTransform(piece.marker, [centerX + Math.cos(yaw * Math.PI / 180) * guideOffset, 0.16, centerZ - Math.sin(yaw * Math.PI / 180) * guideOffset], [0.055, 0.025, length * 0.58], [0, yaw, 0]);
      }
    });
  }

  updateMotorcycle(state, breath, timestamp, settings) {
    const road = sampleRoadAtDistance(state, state.road.travelled);
    const lateral = clamp((state.bike.x - road.centerX) / Math.max(1, road.width), -1.2, 1.2);
    const lean = clamp(state.bike.lean || state.bike.velocityX * 0.025, -1, 1);
    const idle = Math.sin(timestamp * 0.004) * 0.025;
    this.bikeRoot.setPosition(lateral * ROAD_HALF_WIDTH * 0.88, 0.12 + idle, 3.7);
    this.bikeRoot.setEulerAngles(0, 180, lean * -17);
    const preset = motorcyclePreset(settings.motorcycle);
    this.bikeRoot.setLocalScale(preset.scale || 1, preset.scale || 1, preset.scale || 1);
    this.underglow.setLocalScale(1.05 + breath * 0.24, 0.035, 1.7 + breath * 0.35);
    this.materials.cyan.emissiveIntensity = 3.3 + breath * 2.8;
    this.materials.cyan.update();
    const correction = clamp(Math.abs(state.input?.jerk || 0) * 0.6, 0, 1);
    this.materials.magenta.emissiveIntensity = 2.1 + correction * 6;
    this.materials.magenta.update();
    this.bikeLight.setPosition(this.bikeRoot.getPosition().x, 1.05, 2.6);
    this.bikeLight.setEulerAngles(-5, 180, 0);
  }

  updateCamera(state, deltaTime) {
    const focusSample = sampleRoadAtDistance(state, state.road.travelled + 350);
    const current = sampleRoadAtDistance(state, state.road.travelled);
    const targetLookX = clamp((focusSample.centerX - current.centerX) / 34, -10, 10);
    const bikeX = this.bikeRoot.getPosition().x;
    const smoothing = 1 - Math.exp(-deltaTime * 4.8);
    this.cameraX += (bikeX * 0.28 - this.cameraX) * smoothing;
    this.cameraLookX += (targetLookX - this.cameraLookX) * smoothing;
    const landscape = this.width > this.height;
    this.camera.setPosition(this.cameraX, landscape ? 3.5 : 4.35, landscape ? 10.5 : 10.9);
    this.camera.lookAt(this.cameraLookX * 0.62, 0.5, landscape ? -23 : -20);
  }

  updateBeacons(state, breath) {
    const offset = (state.road.travelled * 0.035) % 5.2;
    this.beacons.forEach(beacon => {
      const z = 4 - ((beacon.index * 5.2 + offset) % 134);
      beacon.entity.setPosition(beacon.side * (8.2 + (beacon.index % 3) * 1.2), 1.05, z);
      beacon.entity.setLocalScale(0.075 + breath * 0.025, 1.4 + breath * 0.75, 0.075 + breath * 0.025);
    });
  }

  render(state, timestamp, settings = {}, appPhase = 'intro') {
    const deltaTime = this.lastTimestamp ? Math.min(0.05, Math.max(0, (timestamp - this.lastTimestamp) / 1000)) : 1 / 60;
    this.lastTimestamp = timestamp;
    const breath = state.breathing?.enabled ? state.breathing.visualEnvelope : 0.5;
    const quality = qualityPreset(settings.reducedEffects ? 'low' : settings.quality);
    const biome = this.resolveBiome(state, appPhase);
    this.applyBiome(biome, breath);
    this.app.scene.fog.density = quality.fogLayers > 1 ? 0.014 + (1 - breath) * 0.006 : 0.011;
    this.updateRoad(state, biome);
    this.updateMotorcycle(state, breath, timestamp, settings);
    this.updateCamera(state, deltaTime);
    this.updateBeacons(state, breath);
    this.app.renderNextFrame = true;
  }

  destroy() {
    this.app?.destroy();
  }
}

export function supportsFlow3D() {
  try {
    const canvas = document.createElement('canvas');
    return Boolean(canvas.getContext('webgl2') || canvas.getContext('webgl'));
  } catch {
    return false;
  }
}
