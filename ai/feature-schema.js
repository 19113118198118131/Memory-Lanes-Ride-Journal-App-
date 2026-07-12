// ===============================
// Memory Lanes - ai/feature-schema.js
// The vocabulary the AI layer shares with the rest of the app: the ride
// feature-record version, the post-ride feedback options, and the small set
// of route features the recommender matches on.
//
// Design note: this is the "labels + shapes" file only. No logic, no imports,
// so both the browser and Node tests can read it without side effects.
// ===============================

// Bump when the shape of an extracted ride feature record changes, so stale
// records can be detected and re-extracted rather than silently mismatched.
export const FEATURE_SCHEMA_VERSION = 1;

// Post-ride feedback: the labels the rider taps. Kept deliberately short.
export const MOOD_OPTIONS = [
  { value: 'flowing',   label: 'Flowing' },
  { value: 'twisty',    label: 'Twisty' },
  { value: 'scenic',    label: 'Scenic' },
  { value: 'relaxed',   label: 'Relaxed' },
  { value: 'technical', label: 'Technical' },
  { value: 'mixed',     label: 'Mixed' }
];

// One-tap reasons. Keyed so they store as booleans and read back cleanly.
export const REASON_OPTIONS = [
  { key: 'likedCorners', label: 'Great corners', positive: true },
  { key: 'likedScenery', label: 'Great scenery', positive: true },
  { key: 'goodGroup',    label: 'Good group ride', positive: true },
  { key: 'tooUrban',     label: 'Too urban', positive: false },
  { key: 'tooMotorway',  label: 'Too much motorway', positive: false },
  { key: 'tooLong',      label: 'Too long', positive: false },
  { key: 'tooShort',     label: 'Too short', positive: false }
];

// The features the KNN recommender compares on. This is intentionally the
// HONEST OVERLAP between what a completed ride and a freshly generated planner
// candidate can both provide - no urban/motorway here, because a recorded ride
// has no routing-step metadata to derive them from. Each has a weight (how
// much it shapes "feel") used both for distance and for the "why" explanation.
export const MATCH_FEATURES = [
  { key: 'distanceKm',     weight: 1.0, label: 'ride length' },
  { key: 'elevationGainM', weight: 0.7, label: 'climbing' },
  { key: 'turnsPerKm',     weight: 1.2, label: 'corner density' }
];

// Below this many rides with both a feature record AND an enjoyment rating,
// the recommender stays quiet rather than pretending to know your taste.
export const MIN_LABELLED_RIDES = 4;
