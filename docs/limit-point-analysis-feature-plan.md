# Limit Point Analysis: Development Plan

Status: Phase 0 model and Debug research preview implemented; reality validation remains required
Owner surfaces: Native route planner, planned-route detail, ride replay
Depends on: high-resolution route geometry, corner detection, weather scenarios, replay evidence, versioned analysis storage

## Product Intent

Limit Point Analysis should help a rider study where road geometry may restrict forward visibility before a ride, then review the same locations afterwards. The pre-ride map is the primary product. Post-ride evidence is secondary. Live audio is a separate, last-stage research candidate, not an assumed deliverable.

The feature must build the rider's own observation and limit-point judgement. It must never claim that a bend is safe, recommend a speed, replace the rider's view, or imply that silence means clear road.

## Core Model

For a circular bend with radius `R` and an estimated lateral obstruction clearance `M`, the concept uses:

```text
available sight distance = 2R * acos(1 - M/R)
stopping distance = v*t + v^2/(2a)
estimated sight margin = available sight distance - stopping distance
```

Initial research assumptions:

- Reaction time `t`: scenario value, initially 1.0 second.
- Deceleration `a`: conservative, explicitly labelled scenario values rather than a promise of available grip.
- Obstruction clearance `M`: fixed at 5 metres only for offline calibration experiments.
- Speed `v`: posted or selected legal reference-speed scenario, never a recommended corner speed.

Every output must retain its model version, assumptions, geometry source, confidence, and reason when unavailable.

## Safety Corrections To The Concept

The following constraints are requirements:

- A fixed `M` must never reach a rider-facing absolute claim. The supplied concept's result moved from 66% to 12% flagged corners when `M` changed from 3 to 8 metres; obstruction estimation dominates the answer.
- Do not use green to mean safe or clear. A neutral route layer may identify modelled restriction severity, uncertainty, and locations worth studying. Positive margin is not headroom to spend.
- Do not use the rider's typical pace as the initial pre-ride reference. Start with a clearly labelled legal-speed scenario and never infer permission to maintain that speed.
- Phone GPS cannot reliably measure lane position or prove that the rider moved outward to improve view. Do not score road position from consumer GPS without separate accuracy evidence.
- Weather data does not prove road wetness or grip. A wet scenario is a conservative estimate, not an observation.
- Map geometry cannot see traffic, fog, low sun, temporary works, fallen objects, surface contamination, vegetation growth, or an obstruction missing from map data.
- No score, badge, streak, leaderboard, personal best, or speed target may use sight margin.
- No live cue ships from model confidence alone. It requires independent road validation, false-negative analysis, alarm-load testing, legal review, and an explicit product decision.

## Data Model

### LimitPointAssumptions

- `modelVersion`
- `reactionTimeSeconds`
- `decelerationMetersPerSecondSquared`
- `obstructionClearanceMeters`
- `referenceSpeedMetersPerSecond`
- `surfaceScenario`: dry, wet-conservative, unknown
- `geometrySource`
- `obstructionSource`: fixed-research, map-derived, terrain-derived, unavailable

### LimitPointAssessment

- `cornerID`
- `routeStartIndex`
- `apexIndex`
- `routeEndIndex`
- `radiusMeters`
- `sweepDegrees`
- `availableSightDistanceMeters`
- `stoppingDistanceMeters`
- `estimatedMarginMeters`
- `severity`: study, restricted, materially-restricted
- `confidence`: unavailable, low, medium, reviewed
- `limitations`
- `assumptions`

No `safe`, `clear`, `recommendedSpeed`, or `maximumSpeed` field is permitted.

## Delivery Plan

### Phase 0: Research Harness

- Implement pure Swift sight-distance, stopping-distance, and margin functions.
- Cover dimensional correctness, invalid geometry, numerical boundaries, and monotonicity with tests.
- Reuse versioned corner geometry without coupling the model to SwiftUI.
- Add a local GPX/route batch tool that emits no route coordinates by default.
- Run sensitivity across `M`, reaction time, deceleration, radius noise, and route simplification.

Exit criteria:

- Same inputs always produce the same output.
- Increasing speed never improves margin.
- Increasing reaction time never improves margin.
- Invalid or uncertain geometry returns unavailable rather than a plausible-looking number.
- Fixed-`M` output remains developer-only.

### Phase 1: Reality Validation

- Select known roads with open, tightening, obstructed, and changing-radius bends.
- Record a structured human review at the road, without attempting review while riding.
- Compare model flags with reviewed geometry and label false positives and false negatives.
- Validate radius against higher-resolution road centreline geometry, not only a recorded GPS trace.
- Include multiple devices, riders, road types, seasons, and GPS qualities.
- Define minimum precision, recall, confidence, and coverage with a safety reviewer before implementation starts.

Exit criteria:

- A written validation report exists with labelled evidence and failure modes.
- False negatives are investigated individually.
- The team can explain where the model is unavailable and why.
- Legal advice has reviewed the intended claims and disclaimers.

### Phase 2: Pre-Ride Study Layer

- Analyse planned routes off the main actor.
- Render a restrained route overlay for locations worth studying and uncertainty.
- Let the rider inspect radius, assumed obstruction clearance, reference scenario, estimated distances, confidence, and limitations.
- Provide a global layer explanation that no map state means safe or clear.
- Cache by route geometry hash and model version.

Initial UI language:

> Geometry suggests the view may tighten here. Study the bend, then read the road yourself.

Do not present a good margin as praise, spare capacity, or permission to carry speed.

### Phase 3: Post-Ride Evidence

- Apply the same versioned model to the completed track and linked planned route.
- Show flagged locations as replay-linked evidence.
- Compare the approach scenario with the model estimate without declaring unsafe behaviour.
- Offer one calm reflection prompt, never a grade.
- Keep Limit Point output separate from Rider Craft until both models independently pass calibration.

### Phase 4: Map-Derived Obstructions

- Build per-corner obstruction estimates from OpenStreetMap features, terrain, road cuttings, vegetation, walls, and land use.
- Preserve source timestamps and confidence; stale or absent data must lower confidence.
- Validate obstruction estimates against reviewed corners before replacing fixed-`M` research output.
- Re-run the full legal and perverse-incentive audit before any absolute-distance wording.

This phase is the technical differentiator. It is also the point at which specialist geospatial and legal review becomes essential.

### Phase 5: Live Audio Research Candidate

Live audio is not approved by this plan. It can be considered only after Phases 0 to 4 pass.

Candidate constraints if separately approved:

- Planned routes only; no free-ride inference initially.
- Opt-in and default off.
- Audio only; no visual warning.
- One neutral phrase: "Blind bend ahead."
- No speed, instruction, score, or urgency escalation.
- Silence must be explicitly framed as no information, never confirmation of safety.
- Alert suppression, route-direction matching, stale-location handling, and repeated-alert prevention are mandatory.
- The proposed 200 metre lookahead and negative-20-metre gate are hypotheses to test, not committed constants.

Release requires on-road human-factors testing conducted without distracting the rider, false-negative review, alarm-frequency evidence, fail-silent behaviour, legal approval, and a kill switch.

## Architecture

- `LimitPointAnalyzing`: pure deterministic model protocol.
- `LimitPointAnalyzer`: Sendable implementation with no UI or network dependency.
- `LimitPointGeometryProviding`: high-resolution route and corner geometry.
- `SightObstructionProviding`: fixed research provider first; versioned map/terrain provider later.
- `LimitPointCalibrationReport`: aggregate sensitivity, confidence coverage, and labelled review results.
- `LimitPointAnalysisService`: background orchestration and versioned cache.

SwiftUI receives immutable assessment values. Network, map parsing, geometry processing, and batch analysis must not run on the main actor.

## Storage And Privacy

- Store model version, assumptions, confidence, and derived assessment summaries only when needed.
- Keep raw GPX as source evidence under existing user ownership and deletion rules.
- Never publish sight-margin assessments in public shares by default.
- Include assessments and assumptions in account export if persisted.
- Deleting a route or ride deletes its cached assessment.

## Definition Of Done

- Formula and monotonicity tests pass.
- Geometry and obstruction uncertainty are visible, not hidden in a single number.
- Fixed-obstruction experiments never surface as absolute rider guidance.
- Representative reality validation and legal review pass.
- No wording implies safe, clear, recommended speed, or available headroom.
- Every post-ride assessment links to replay evidence.
- Pre-ride analysis remains useful with live cues completely disabled.
- Recording, navigation, replay, and route planning still work when analysis is unavailable.

## Current Decision

Add Limit Point Analysis to the native roadmap immediately. Begin only with Phase 0 after the current Rider Craft calibration replay work. Do not schedule live audio, patent claims, or rider-facing absolute stopping-distance claims until the evidence and legal gates above are satisfied.

## Research Preview Status

The native Debug build now includes:

- Pure Swift sight-distance, stopping-distance, and margin calculations.
- Sustained-bend geometry detection with deterministic formula and route fixtures.
- A planned-route study map with selectable legal reference-speed scenarios.
- A post-ride review using recorded entry speed and replay-linked bend evidence.
- Dry and conservative wet stopping scenarios, with limitations shown beside the result.

The preview deliberately uses the fixed five-metre obstruction assumption from Phase 0 and is therefore gated by `LimitPointFeature.isResearchPreviewEnabled`. It is visible in Debug builds for controlled evaluation and hidden in Release builds. It is not a production safety system.

Still required before production rollout:

- Structured reality validation on reviewed roads and higher-resolution geometry.
- Documented false-positive and false-negative performance.
- A versioned map/terrain obstruction provider with confidence and staleness handling.
- Safety, human-factors, and legal review of every rider-facing claim.
- Live audio remains unbuilt and unapproved; it is not required for the pre-ride and post-ride product.
