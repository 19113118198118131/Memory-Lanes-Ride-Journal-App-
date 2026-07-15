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

- [x] define a stable, versioned on-device graph archive contract
- [x] add a Supabase Storage catalog and pack-download contract
- [x] verify size and SHA-256 before atomic pack activation
- [x] expose rider-selected Offline Areas, updates and storage controls
- [x] build deterministic regional graph packs from licensed OSM extracts in CI
- [x] sign and verify release manifests with an app-pinned Ed25519 key
- [x] publish immutable packs before the catalog through Supabase Storage S3
- [x] block releases on archive integrity, mainland connectivity and route probes
- [x] bound compressed and decoded pack size before publication
- [ ] configure production release secrets and publish the first Auckland pack
- retain OSM attribution and ODbL notices
- [x] add installed graph-version and routing-fallback telemetry

### Phase 3: on-device routing

Cross-pack routing must use a compact boundary index or binary graph format. Two decoded v1 JSON graphs must not be held in memory together because the measured per-pack memory cost would make that unsafe on older supported iPhones.

- [x] download only rider-selected regions
- [x] verify pack checksums before activation
- [x] load and spatially index activated graph packs off the main actor
- [x] snap route points to downloaded roads and run turn-aware A* locally
- [x] enforce one-way, node-via and way-via turn restrictions
- [x] populate road-class and surface context for proprietary route scoring
- [x] snap waypoints to a shared weakly connected road component
- [x] prefer the embedded provider and fall back to MapKit outside local coverage
- [ ] route seamlessly across adjacent installed packs
- [ ] support offline in-ride rerouting
- [x] validate load, indexing and representative routes against the first Auckland build

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

Offline routing diagnostics are coordinate-free and remain on the rider's
iPhone. They retain aggregate local-route and fallback counts, the last pack ID
and version, duration, and a bounded failure reason. Waypoints, route geometry,
road names and rider location are never included.
