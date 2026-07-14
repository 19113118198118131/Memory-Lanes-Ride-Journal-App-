# Rider Craft Phase 1 Calibration

Date: 2026-07-14
Engine: Rider Craft threshold version 1
Status: Calibration incomplete; production rollout remains disabled

## Dataset

The native production analyzer was run locally over nine real GPX rides already stored by Memory Lanes. Raw GPX files and route coordinates were not added to Git, and the generated report contains only anonymous file labels, counts, signal values, and replay indices.

| Measure | Result |
|---|---:|
| GPX rides | 9 |
| Eligible rides | 9 |
| GPS points per ride | 516 to 19,796 |
| Detected corners | 991 |
| Candidate events | 806 |
| Candidate events per corner | 0.813 |

This is useful same-rider calibration evidence, but it is not yet representative across riders, regions, GPS devices, road types, or weather. It cannot by itself approve a production release.

## Version 1 Results

| Detector | Threshold | Events | Rate per detected corner | Decision |
|---|---:|---:|---:|---|
| Braking after turn-in | Any braking-zone start after turn-in | 20 | 2.0% | Plausible; replay review still required |
| Flat exit | `drive < 0.10` | 197 | 19.9% | Too broad to approve without replay review |
| Early apex | `apexPosition <= 0.35` | 491 | 49.5% | Rejected for production |
| Braked deep | `brakeDepth > 0.60` | 98 | 9.9% | Plausible; replay review still required |

The apex-position distribution has a median of 0.375 and a lower quartile of 0.048. The current apex proxy is the minimum-speed point within a detected corner, so braking and corner-boundary estimation can pull it towards the start of the corner. That is not reliable evidence of road position or line choice.

## Threshold Sensitivity

Early-apex remained too frequent at every tested threshold:

| Maximum apex position | Event rate |
|---:|---:|
| 0.10 | 28.1% |
| 0.15 | 32.2% |
| 0.20 | 35.8% |
| 0.25 | 40.8% |
| 0.30 | 44.0% |
| 0.35 | 49.5% |

The detector must not be fixed by merely lowering the threshold. It needs an eligibility model that can distinguish corner geometry and a replay review that confirms the signal traces the rider's line. If that evidence cannot be obtained from phone GPS, remove the detector rather than presenting an uncertain claim.

Flat-exit sensitivity was 11.0% at `drive < 0` and 14.8% at `drive < 0.05`, compared with 19.9% at the current `drive < 0.10`. A zero threshold is the next candidate because it describes continued deceleration rather than rewarding greater acceleration. It still requires replay review and must never become a speed target.

Braked-deep sensitivity ranged from 13.9% at a depth of 0.40 to 4.9% at 0.80. The current 0.60 threshold is retained only as a calibration candidate. Braking-after-turn-in ranged from 2.0% for any overlap to 1.1% when braking began past half of the detected corner.

## Perverse-Incentive Audit

| Question | Finding |
|---|---|
| Can the headline improve by riding faster? | Event counts do not directly use speed, but exit-drive advice could encourage acceleration if worded as performance. It must remain post-ride, evidence-linked, and framed around a settled progressive input only after the exit is visible. |
| Can the headline improve through a riskier line? | The early-apex proxy could encourage riders to chase a later line despite missing road, lane, traffic, and sight-line context. The detector is rejected for production in version 1. |
| Can a rider game the metric? | A rider could avoid detected events by riding unusually slowly or by producing sparse/noisy GPS. No badge, streak, score, or reward may use these events. Poor data must return unavailable. |
| Does the app claim evidence it lacks? | Phone GPS cannot observe gaze, lane position, brake pressure, throttle position, grip, hazards, or intent. Copy must say detected pattern or proxy, never mistake or unsafe behaviour. |
| Is coaching delivered during the ride? | No. Rider Craft remains post-ride only and cannot interrupt recording or navigation. |

Audit result: **not approved for public rollout**. The existing production gate and stored `calibrated: false` value remain correct.

## Next Review

1. Add a calibration-only replay surface that opens each event at its stored replay index.
2. Manually label a balanced sample of event and non-event corners for the three plausible detectors.
3. Replace or remove early-apex before any Rider Craft UI is enabled.
4. Re-run the report with versioned candidate thresholds and add regression fixtures for confirmed false positives.
5. Repeat with additional riders, road types, GPS qualities, and weather before changing `calibrated` to true.

## Reproducing The Aggregate Report

Keep GPX files outside the repository, then run:

```sh
scripts/run-rider-craft-calibration.sh /path/to/gpx-directory /tmp/rider-craft-report.json
```

The tool compiles and runs the same `GPXParser`, `RideCoachAnalyzer`, and `RiderCraftAnalyzer` used by the native app. It emits aggregate distributions, threshold sensitivity, anonymous per-ride counts, and replay-linked event measurements without emitting route coordinates.
