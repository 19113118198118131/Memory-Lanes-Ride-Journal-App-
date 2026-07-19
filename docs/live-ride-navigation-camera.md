# Live Ride Navigation Camera

## Purpose

The live camera is a glanceable map instrument for an active recording. When a
planned route is selected, the cockpit also prepares road-aware MapKit steps,
spoken maneuver prompts and sustained off-route recovery. Recording, background
location, draft recovery and ride saving remain independent from navigation and
camera presentation.

## Behaviour

- heading-up while reliable movement is detected
- north-up option at any time
- flat north-up presentation when Reduce Motion is enabled
- 18-second forward time horizon with a 120-metre minimum
- speed-smoothed camera distance and pitch
- low-speed bearing freeze with engage and release hysteresis
- shortest-arc bearing interpolation across north
- maximum 28-degree bearing change per accepted GPS update
- forward-shifted camera centre while moving
- manual map interaction suspends following until the rider recentres
- road-aware maneuver instructions and remaining distance/ETA for planned rides
- spoken prompts at one kilometre, 300 metres and the maneuver
- background spoken prompts while the screen is locked, with audio ducking
  released after each instruction
- a 12-second off-route hold before recalculation, avoiding noisy-GPS reroutes
- automatic road recalculation with a 45-second retry cooldown
- geometric saved-route guidance when road directions are unavailable

`LiveRideCameraController` is deterministic and has no MapKit dependency.
`LiveRideMapView` translates its output into `MKMapCamera` updates. This keeps
camera calibration testable without a live GPS session or rendered map.

`TurnByTurnNavigationEngine` is also deterministic and MapKit-independent. It
matches GPS fixes to route geometry, keeps progress monotonic through noisy
fixes and loops, selects the next road instruction, derives ETA and detects
arrival. Installed graph packs now generate conservative maneuvers at meaningful
named-road and bearing changes; sustained off-route recovery uses the same
offline provider. `MapKitTurnByTurnRouteProvider` remains the automatic fallback
outside downloaded coverage or when a local graph cannot serve the whole route.

## Automated validation

The camera suite includes the repository's 550-point coast-and-hills GPX. It
derives speed and course from each timed segment and verifies:

- camera distance stays between 240 and 1,600 metres
- pitch stays between 0 and 50 degrees
- bearing never changes by more than 28.01 degrees per update
- pitch does not pump by 12 degrees or more per update
- crossing from 355 to 5 degrees uses a positive 10-degree shortest arc
- low-speed hysteresis holds the last trustworthy bearing

## On-road acceptance checklist

Test with the phone securely mounted and do not operate controls while moving.

1. Start stationary in several orientations. The map should remain calm.
2. Pull away slowly. Heading-up should engage progressively, without a snap.
3. Cross north in both directions. The map should take the short rotation.
4. Stop at lights. Bearing should remain stable and pitch should settle flat.
5. Ride at urban and open-road speeds. The visible road horizon should expand
   without obvious zoom pumping.
6. Pan the map while stopped. Following should pause and the recenter control
   should restore it.
7. Repeat in landscape and portrait. The rider should stay in the lower part of
   the useful map area without being obscured by the ride HUD.
8. Enable Reduce Motion. The map should remain flat, north-up and unanimated.
9. Start a saved route and verify each maneuver card and spoken prompt agrees
   with the road ahead. Voice can be muted from the map control.
10. Deliberately miss a safe turn. Guidance should wait through brief GPS drift,
    then show recalculation and return to road instructions without interrupting
    recording.
11. Disable network access after guidance has loaded. Recording must continue;
    a failed recalculation must retain the saved-route fallback rather than end
    the ride.

The MapKit camera-distance multiplier is an empirical starting point. Adjust it
only after comparing these scenarios on a mounted physical device.
