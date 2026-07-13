// ===============================
// Memory Lanes - ai/ride-feedback.js
// The post-ride "how did this feel?" card. Renders the mood / enjoyment /
// would-repeat / reasons choices, loads any answer already saved, and writes
// changes straight back to ride_logs.feedback. Every tap auto-saves - there's
// no separate Save button to forget.
// ===============================

import supabase from '../supabaseClient.js';
import { MOOD_OPTIONS, REASON_OPTIONS } from './feature-schema.js?v=90';

const ENJOYMENT = [1, 2, 3, 4, 5];
const REPEAT = [
  { value: 'yes', label: 'Yes' },
  { value: 'maybe', label: 'Maybe' },
  { value: 'no', label: 'No' }
];

function chip(label, active) {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'feedback-chip' + (active ? ' active' : '');
  b.textContent = label;
  return b;
}

/**
 * Mount the feedback card for a saved ride.
 * @param {string} rideId
 * @param {object} existing  ride_logs.feedback jsonb (or null)
 */
export function initRideFeedback(rideId, existing) {
  const section = document.getElementById('ride-feedback-section');
  if (!section || !rideId) return;
  section.style.display = '';

  const state = {
    mood: existing?.mood ?? null,
    enjoyment: Number.isFinite(existing?.enjoyment) ? existing.enjoyment : null,
    wouldRepeat: existing?.wouldRepeat ?? null,   // 'yes' | 'maybe' | 'no'
    reasons: { ...(existing?.reasons || {}) }
  };
  const statusEl = document.getElementById('feedback-status');

  let saveTimer = null;
  async function save() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(async () => {
      statusEl.textContent = 'Saving...';
      const payload = {
        mood: state.mood,
        enjoyment: state.enjoyment,
        wouldRepeat: state.wouldRepeat,
        reasons: state.reasons,
        at: new Date().toISOString()
      };
      const { error } = await supabase.from('ride_logs').update({ feedback: payload }).eq('id', rideId);
      statusEl.textContent = error ? 'Could not save feedback.' : 'Saved. This shapes your route matches.';
    }, 350);
  }

  // Mood (single choice)
  const moodWrap = document.getElementById('feedback-mood');
  moodWrap.innerHTML = '';
  MOOD_OPTIONS.forEach(o => {
    const b = chip(o.label, state.mood === o.value);
    b.addEventListener('click', () => {
      state.mood = state.mood === o.value ? null : o.value;
      moodWrap.querySelectorAll('.feedback-chip').forEach((el, i) =>
        el.classList.toggle('active', MOOD_OPTIONS[i].value === state.mood));
      save();
    });
    moodWrap.appendChild(b);
  });

  // Enjoyment 1..5 (single choice)
  const enjoyWrap = document.getElementById('feedback-enjoyment');
  enjoyWrap.innerHTML = '';
  ENJOYMENT.forEach(n => {
    const b = chip(String(n), state.enjoyment === n);
    b.classList.add('feedback-chip-num');
    b.addEventListener('click', () => {
      state.enjoyment = state.enjoyment === n ? null : n;
      enjoyWrap.querySelectorAll('.feedback-chip').forEach((el, i) =>
        el.classList.toggle('active', ENJOYMENT[i] === state.enjoyment));
      save();
    });
    enjoyWrap.appendChild(b);
  });

  // Would repeat (single choice)
  const repeatWrap = document.getElementById('feedback-repeat');
  repeatWrap.innerHTML = '';
  REPEAT.forEach(o => {
    const b = chip(o.label, state.wouldRepeat === o.value);
    b.addEventListener('click', () => {
      state.wouldRepeat = state.wouldRepeat === o.value ? null : o.value;
      repeatWrap.querySelectorAll('.feedback-chip').forEach((el, i) =>
        el.classList.toggle('active', REPEAT[i].value === state.wouldRepeat));
      save();
    });
    repeatWrap.appendChild(b);
  });

  // Reasons (multi-select toggles)
  const reasonWrap = document.getElementById('feedback-reasons');
  reasonWrap.innerHTML = '';
  REASON_OPTIONS.forEach(o => {
    const b = chip(o.label, !!state.reasons[o.key]);
    b.classList.add(o.positive ? 'feedback-chip-pos' : 'feedback-chip-neg');
    b.addEventListener('click', () => {
      state.reasons[o.key] = !state.reasons[o.key];
      b.classList.toggle('active', state.reasons[o.key]);
      save();
    });
    reasonWrap.appendChild(b);
  });
}
