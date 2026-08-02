// A small procedural soundscape keeps Flow fully offline and avoids shipping a
// loud or branded engine recording. Audio is best-effort: gameplay never waits
// for Web Audio and continues silently when a browser blocks it.

export class FlowAudio {
  constructor() {
    this.context = null;
    this.master = null;
    this.ambientGain = null;
    this.filter = null;
    this.oscillators = [];
    this.enabled = true;
    this.flowAmount = 0.68;
    this.breathEnvelope = 0;
    this.breathPhase = 'inhale';
  }

  async unlock() {
    if (!this.enabled) return false;
    const AudioContextClass = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!AudioContextClass) return false;
    try {
      if (!this.context) this.createGraph(new AudioContextClass());
      if (this.context.state === 'suspended') await this.context.resume();
      return this.context.state === 'running';
    } catch {
      return false;
    }
  }

  createGraph(context) {
    this.context = context;
    this.master = context.createGain();
    this.master.gain.value = 0.18;
    this.master.connect(context.destination);

    this.filter = context.createBiquadFilter();
    this.filter.type = 'lowpass';
    this.filter.frequency.value = 1100;
    this.filter.Q.value = 0.7;
    this.ambientGain = context.createGain();
    this.ambientGain.gain.value = 0.045;
    this.ambientGain.connect(this.filter);
    this.filter.connect(this.master);

    for (const [frequency, gain] of [[55, 0.7], [82.5, 0.22], [110, 0.08]]) {
      const oscillator = context.createOscillator();
      const voiceGain = context.createGain();
      oscillator.type = frequency === 55 ? 'sine' : 'triangle';
      oscillator.frequency.value = frequency;
      voiceGain.gain.value = gain;
      oscillator.connect(voiceGain);
      voiceGain.connect(this.ambientGain);
      oscillator.start();
      this.oscillators.push(oscillator);
    }
  }

  setEnabled(enabled) {
    this.enabled = Boolean(enabled);
    if (!this.context || !this.master) return;
    const now = this.context.currentTime;
    this.master.gain.cancelScheduledValues(now);
    this.master.gain.setTargetAtTime(this.enabled ? 0.18 : 0.0001, now, 0.08);
  }

  setFlow(flow) {
    if (!this.context || !this.filter || !this.ambientGain || !this.enabled) return;
    this.flowAmount = Math.max(0, Math.min(1, Number(flow) / 100));
    this.applyModulation();
  }

  setBreathing(envelope, phase = 'inhale') {
    this.breathEnvelope = Math.max(0, Math.min(1, Number(envelope) || 0));
    this.breathPhase = phase === 'exhale' ? 'exhale' : 'inhale';
    if (!this.context || !this.filter || !this.ambientGain || !this.enabled) return;
    this.applyModulation();
  }

  applyModulation() {
    if (!this.context || !this.filter || !this.ambientGain || !this.enabled) return;
    const now = this.context.currentTime;
    const phaseWarmth = this.breathPhase === 'exhale' ? -90 : 80;
    this.filter.frequency.setTargetAtTime(
      420 + this.flowAmount * 900 + this.breathEnvelope * 250 + phaseWarmth,
      now,
      0.2,
    );
    this.ambientGain.gain.setTargetAtTime(
      0.025 + this.flowAmount * 0.025 + this.breathEnvelope * 0.012,
      now,
      0.24,
    );
  }

  apex(quality = 'clean') {
    if (!this.context || !this.master || !this.enabled) return;
    const frequency = quality === 'perfect' ? 660 : quality === 'clean' ? 550 : 440;
    this.chime(frequency, quality === 'perfect' ? 0.17 : 0.11);
  }

  streak() {
    if (!this.context || !this.master || !this.enabled) return;
    this.chime(440, 0.08, 0);
    this.chime(660, 0.07, 0.08);
  }

  complete() {
    if (!this.context || !this.master || !this.enabled) return;
    this.chime(440, 0.09, 0);
    this.chime(550, 0.09, 0.11);
    this.chime(660, 0.12, 0.22);
  }

  chime(frequency, volume, delay = 0) {
    const start = this.context.currentTime + delay;
    const oscillator = this.context.createOscillator();
    const gain = this.context.createGain();
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(frequency, start);
    oscillator.frequency.exponentialRampToValueAtTime(frequency * 1.015, start + 0.32);
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(volume, start + 0.025);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.55);
    oscillator.connect(gain);
    gain.connect(this.master);
    oscillator.start(start);
    oscillator.stop(start + 0.6);
  }

  setPaused(paused) {
    if (!this.context || !this.ambientGain || !this.enabled) return;
    if (paused) this.ambientGain.gain.setTargetAtTime(0.006, this.context.currentTime, 0.12);
    else this.applyModulation();
  }

  dispose() {
    for (const oscillator of this.oscillators) {
      try { oscillator.stop(); } catch {}
    }
    this.oscillators = [];
    if (this.context) this.context.close().catch(() => {});
    this.context = null;
  }
}
