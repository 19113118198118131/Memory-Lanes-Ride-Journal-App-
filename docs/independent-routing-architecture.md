# Memory Lanes Independent Routing

## Product position

Memory Lanes owns the rider-preference and road-character intelligence. A route
provider is a replaceable pathfinding component, not the product model. Apple
MapKit remains the native presentation layer.

## Runtime layers

1. `RoadRouteProviding` finds a connected, legally routable path through a set
   of waypoints.
2. `RouteCharacterAnalyzer` evaluates geometry and optional road context using
   a versioned Memory Lanes model.
3. `IndependentRoutePlanner` generates diverse loops, evaluates candidates and
   exposes explainable scores.
4. `RideRecommendationEngine` personalises ranking from the rider's rated rides.
5. SwiftUI renders the result with MapKit.

The current `MapKitRoadRouteProvider` is a fallback. It returns geometry-only
context and its output is evaluated transiently. It is not used to build a
stored road database or train a mapping service.

## Model inputs

Geometry inputs available now:

- sampled heading changes
- turns per kilometre
- tighter-turn proportion
- bend continuity
- heading variety
- straight-road proportion

OSM graph packs will later provide:

- road class and legal motorcycle access
- surface and smoothness
- motorway and urban proportions
- land use, water, forest and protected-area proximity
- elevation and grade
- turn restrictions and conditional access

Missing inputs remain missing. The UI labels geometry-only assessments as
`Geometry preview`; it does not invent scenery, elevation or surface quality.

## Independence phases

### Phase 1: provider seam and proprietary scoring

- MapKit fallback behind `RoadRouteProviding`
- versioned route-character model
- explainable candidate scoring
- personal ranking blended with road character

### Phase 2: OSM graph-pack pipeline

- build regional graph tiles from licensed OSM extracts in CI
- publish signed, versioned manifests and packs to Supabase Storage
- retain OSM attribution and ODbL notices
- add data-quality and graph-version telemetry

### Phase 3: on-device routing

- download only rider-selected regions
- verify pack checksums before activation
- support offline pathfinding and rerouting
- populate enriched road context
- keep the provider replaceable while validating the embedded engine

### Phase 4: learning-to-rank

- train only from consented Memory Lanes ride and feedback data
- retain safety constraints as hard filters, never learned preferences
- calibrate population priors separately from private rider adaptation
- version every feature schema and model release

## Safety and licensing

Route character is an enjoyment estimate, not evidence that a road is safe or
clear. Legal access, closures, surface suitability and routing restrictions are
hard constraints. OSM attribution is required anywhere OSM-derived results are
presented. Apple MapKit data is not harvested into the proprietary graph.
