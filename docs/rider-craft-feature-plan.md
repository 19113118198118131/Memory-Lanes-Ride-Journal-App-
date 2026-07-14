# Rider Craft: Safety-First Skill Progression

Status: Phase 1 implemented; real-ride calibration pending
Owner surface: Native SwiftUI app
Depends on: Ride Coach analytics, corner replay, weather, persisted skill history

## Product Rule

Nothing in Rider Craft may be improved by riding faster, leaning further, or taking more risk. A proposed metric, badge, target, or interaction does not ship if a rider can improve it through riskier public-road riding.

Rider Craft rewards error reduction, smooth inputs, predictability, and reflection. It is post-ride only. It does not use leaderboards, streaks, live prompts, pace achievements, lean-angle achievements, or fabricated composite scores.

## Supported Signals

The current deterministic engine can support four candidate survival-reaction detectors:

| Detector | Existing signal | Initial threshold | Calibration note |
|---|---|---:|---|
| Braking after turn-in | Braking zone begins inside detected corner | Event overlap | Validate turn-in boundary |
| Flat exit | `corner.drive` | `< 0.10` | Likely too strict; calibrate first |
| Early apex | `corner.apexPosition` | `<= 0.35` | May reflect road geometry |
| Braked deep | `corner.brakeDepth` | `> 0.60` | Validate across varied roads |

Each event must retain its corner and replay index so the rider can inspect the evidence on the map.

Do not implement a throttle-chop detector. At 1 Hz GPS, a genuine chop cannot be separated reliably from not accelerating, and the current apex definition makes a post-apex speed-drop detector mathematically invalid. Use exit drive only as an honest proxy.

## Headline Metric

The primary measure is **survival reactions per corner**, an error rate that should fall over time:

> 0.81 survival reactions per corner. Down from 1.12 across your last five rides.

This is not a score or grade. It is a normalised count of named, correctable events that GPS can support. The app must show an unavailable state when track quality or corner count is insufficient.

## Delivery Plan

### Phase 1: Detection and Calibration

- Implement the four detectors in Swift alongside `RideCoachAnalyzer`.
- Return total counts, per-corner rate, category counts, and replay-linked events.
- Add one restrained debrief line only; do not add a new dashboard yet.
- Run detectors against a representative batch of real rides.
- Record false positives and threshold changes in tests and calibration notes.
- Keep the metric behind a feature flag until the evidence review passes.

Exit criteria:

- Detector results are reproducible from the same GPX.
- Synthetic fixtures cover positive and negative cases.
- Real-ride review includes different roads, durations, GPS qualities, and weather.
- Early-apex and flat-exit thresholds have explicit calibration evidence.
- The written perverse-incentive audit concludes that no metric improves through added risk.

### Phase 2: One Skill at a Time

- Select one focus from corner entry, exit drive, consistency, braking feel, or throttle feel.
- Hold the focus for a defined period rather than changing it after every ride.
- Show one skill, one drill, and one measurable target.
- Score other axes internally but keep them visually secondary.
- Treat regression calmly and avoid shame or urgency.

Example:

> This month: Exit Drive. Your exits were flat on 18% of detected corners. Practise one progressive roll-on once the exit is visible. Target: below 10%.

### Phase 3: Safety-Positive Badges

Only badges that cannot be improved by speed or risk are eligible:

| Badge | Evidence |
|---|---|
| Settled Entry | 20 consecutive detected corners with braking completed before turn-in |
| Late Apex Habit | Late apex on at least 70% of eligible blind-corner proxies, after validation |
| Smooth Hands | Braking and throttle smoothness both above 80 |
| Repeatable | Consistency above 70 across comparable corner-radius groups |
| Wet Discipline | Lower median cornering load on a weather-confirmed wet ride |

Badge exclusions: distance, maximum speed, lean angle, corner count, ride count, frequency, and streaks.

### Phase 4: Personal Progress

- Add a Craft surface showing survival reactions per corner over time.
- Show category trends and the current focus.
- Compare the rider only with their own recent baseline.
- Do not rank riders or expose public comparisons.
- Do not punish breaks, missed rides, or one-off regressions.

### Phase 5: Road Sense Education

GPS cannot score observation, hazard perception, lane discipline, road positioning, sight lines, or judgement around other traffic. Teach these topics contextually but never assign a number.

Possible unscored cards:

- Tightening-bend geometry: late apex and preserving sight line.
- Wet weather: smooth inputs, grip margin, and stopping distance.
- Junction-heavy ride composition: covering the brake and positioning for view.

Never display a Road Sense score. It would imply evidence the app does not possess.

## Safety Refusals

- No speed, pace, lean-angle, lateral-g, or maximum-performance achievements.
- No cross-rider leaderboards.
- No streaks or frequency pressure.
- No live gamification or coaching during a ride.
- No fabricated composite progression score.
- No unsupported interpretation of GPS noise as rider behaviour.

## Data and Architecture

- Keep detection deterministic, testable, and separate from generated language.
- Store detector schema version, thresholds, counts, per-corner rate, and replay-linked event summaries in the existing `skills` payload or a versioned successor.
- Preserve raw GPX as the source evidence.
- Compute trends against a bounded recent history.
- Allow thresholds to evolve by schema version without rewriting old results silently.
- Ensure Rider Craft remains optional and never blocks recording, saving, replay, or Ride Coach.

## Definition of Done

A Rider Craft phase is done only when it satisfies the app-wide definition of done plus:

- Every number traces to a documented signal and threshold.
- Poor-quality data produces an unavailable state.
- Advice is post-ride, specific, calm, and evidence-linked.
- The perverse-incentive audit is written and passed.
- Real-ride calibration evidence exists beyond the original two validation rides.

## First Development Slice

Build Phase 1 only: four detectors, event models with replay indices, synthetic tests, calibration fixtures, and one honest Ride Coach debrief line. Do not begin the focus system, badges, or Craft page until the detector review passes.

## Implementation Status

Completed in native SwiftUI:

- Versioned thresholds and four deterministic detectors.
- Replay-linked event evidence with measured values and thresholds.
- Honest insufficient-corner state; the event rate requires at least three detected corners.
- Versioned storage inside the existing `skills.craft` payload with `calibrated: false`.
- Positive, negative, insufficient-data, debrief, replay-link, and storage fixtures.
- A rollout gate that keeps calibration copy out of production UI.

Still required before Phase 1 can surface publicly:

- Run the detector output across a representative batch of real rides.
- Review false positives by replaying the linked corners.
- Revisit the flat-exit and early-apex thresholds using that evidence.
- Record and pass the Phase 1 perverse-incentive audit.
- Change the stored calibration status only through a versioned threshold release.
