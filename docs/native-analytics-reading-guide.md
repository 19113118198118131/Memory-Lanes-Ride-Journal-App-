# Native Ride Analytics: How To Read It

The native app preserves the original web app's analysis depth while presenting it in layers. A rider should see the main story first, inspect the visual evidence second, and open technical interpretation only when they want it.

## Presentation Order

1. Ride Insights: one plain-English observation, with the remaining observations collapsed.
2. How to Read: a collapsed guide covering every visual.
3. Elevation and Speed Profile: road shape and ride rhythm over distance.
4. Corner Speed vs Radius: detected corner geometry with constant-load reference curves.
5. Acceleration Profile: braking and drive zones over smoothed longitudinal acceleration.
6. Grip Usage: the approximate lateral/longitudinal GPS signature.
7. Ride Coach: debrief, five-axis technique polygon, trend, and expandable captions.
8. Ride Rhythm: time composition across cornering, braking, driving, cruising, and stopped states.

## Reading Rules

### Elevation And Speed

Elevation and speed use independent display scales so their shapes can be compared. A speed dip can be caused by a corner, climb, junction, stop, traffic, or GPS noise. It is evidence to inspect on the map, not a conclusion by itself.

### Corner Speed Vs Radius

Each dot is a detected bend. Smaller radius means a tighter bend. Vertical spread at a similar radius shows that geometrically similar bends were approached differently. Dashed load curves are references, never targets or encouragement to ride faster.

### Acceleration

Values below zero indicate deceleration and values above zero indicate drive. Shaded bands show detected braking and drive zones. Smooth alternation can reveal rhythm; spikes can indicate abrupt input or noisy sampling.

### Grip Usage

Left and right represent estimated cornering force. Down represents braking and up represents drive. The point cloud is a riding signature, not a score, available grip estimate, or shape to maximise.

### Ride Coach

The polygon compares corner entry, exit drive, braking feel, throttle feel, and consistency. Its balance is more useful than its size. Captions explain the evidence behind each axis, and a single ride is never a verdict.

### Rider Craft

Detections per corner is a normalised count of four GPS-supported patterns, not a score. Detector tiles show category counts. Every event links to replay because geometry, traffic, sampling, and GPS noise can explain a detection. While the feature is marked Calibrating, all output is a research prompt rather than proof of rider error.

## Interaction

- Dragging over elevation, speed, or acceleration keeps the chart visible and reveals local values.
- Releasing on a replay-capable point returns to the map and frames the local approach and exit.
- Corner dots and Rider Craft evidence use the same map-focus behaviour.
- Explanatory content is collapsed by default to keep the ride page calm and scannable.

## Safety Language

All analytics are GPS-derived estimates for reflection. No chart, curve, score, polygon, detection, or positive trend is permission to increase speed, lean, braking force, or risk on a public road.
