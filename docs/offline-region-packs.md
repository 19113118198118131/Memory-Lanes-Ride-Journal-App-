# Offline Areas

## Product contract

Riders manage one offline-area product from **Account -> Offline Maps**. The map
selector offers 25 km, 60 km and 120 km starting sizes. The rider moves and
zooms the map, names the selection, and downloads the highlighted bounds once.
The app then stores the visual map and automatically installs every published
routing pack intersecting that selection. The separate file formats and release
catalog are implementation details and are not exposed as another download.

Visual maps use MapLibre Native offline packs. Each pack stores its bounds,
name, zoom range, progress and downloaded resources in MapLibre's local
database. Downloads survive relaunch, can be resumed, renamed and removed, and
render from the local database when the network is unavailable. The initial
style endpoint is OpenFreeMap's Liberty style. `OfflineMapServing` keeps that
provider replaceable so production hosting can move to Memory Lanes
infrastructure without changing feature UI or stored metadata.

The live recording cockpit selects that MapLibre surface automatically when
the rider or planned route is inside a completed downloaded area. It retains
the same forward-looking camera, route casing, rider puck and live group-rider
markers. Outside downloaded map coverage the cockpit uses Apple Maps. This
keeps the user contract simple: one downloaded area supplies the visible map
and, where published, the road graph used for planning, maneuvers and rerouting.

Signed `.mlgraph` road graphs calculate routes and turn-by-turn guidance without
reception where graph coverage exists. Existing map-only downloads offer a
single **Finish Setup** action when matching route data is available. An area
card reports whether the entire area or only part of it has offline routing;
map-only selections remain usable and explain when routing data has not yet
been published. MapKit remains the automatic online fallback until an installed
graph covers every route waypoint.

Removing an offline area also removes intersecting road data when no other
downloaded area still uses it. Saved routes and recorded rides are unaffected.

## Storage layout

The public Supabase Storage bucket is `offline-regions`:

```text
offline-regions/
  manifest.json
  packs/
    nz-auckland-north-v1.mlgraph
```

Run `supabase-offline-regions-setup.sql` once. The iOS client has no write
policy; releases are published by `.github/workflows/offline-graph-release.yml`
with server-only Supabase S3 credentials.

## Signed manifest schema

`manifest.json` is an Ed25519-signed envelope. The iOS client pins the release
public key, verifies the signature over the exact payload bytes, then decodes
and validates the manifest. Unverified network or cached catalogs are rejected.

```json
{
  "schemaVersion": 1,
  "keyID": "release-2026-08",
  "payload": "<base64 canonical manifest JSON>",
  "signature": "<base64 Ed25519 signature>"
}
```

The decoded payload is:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-07-15T08:00:00Z",
  "regions": [
    {
      "id": "nz-auckland-north",
      "name": "Auckland North",
      "detail": "North Shore, Hibiscus Coast, Warkworth and Matakana",
      "bounds": {
        "south": -36.85,
        "west": 174.5,
        "north": -36.3,
        "east": 174.85
      },
      "version": 1,
      "formatVersion": 1,
      "encoding": "deflate-json",
      "byteCount": 6149934,
      "sha256": "<64-character lowercase SHA-256>",
      "downloadPath": "packs/nz-auckland-north-v1.mlgraph",
      "updatedAt": "2026-07-15T08:00:00Z"
    }
  ]
}
```

The client rejects unknown signing keys, invalid signatures, duplicate IDs,
unsafe paths, unsupported versions, invalid bounds, size mismatches and checksum
mismatches. Downloads are staged and only replace an installed pack after
verification succeeds.

## Graph format v1

`.mlgraph` is deterministic raw-DEFLATE canonical JSON matching
`OfflineRoadGraphArchive`:

- directed nodes and edges suitable for one-way and turn-aware expansion;
- distance and expected travel time per edge;
- OSM way ID, road class, surface, optional road name and posted maximum speed;
- node-via and way-via prohibited or only-turn restrictions, retaining raw
  conditional text for conservative runtime evaluation;
- region bounds, generation timestamp and OSM attribution.

`tools/offline_graph/build_graph.py` excludes unsupported road classes,
service aisles and driveways, construction geometry, private access, motorcycle
prohibitions and ferry paths;
it preserves explicit motorcycle overrides, one-way direction and supported
OSM turn restrictions.

The native app inflates and validates an activated pack off the main actor,
builds a coarse spatial index, finds nearby nodes in each weakly connected road
component and snaps every planning point to the best component shared by the
whole route. This avoids selecting an isolated driveway fragment just because
it is marginally closer than the connected road network. It then runs a
turn-aware A* search optimized for expected travel time. The search
enforces directed edges plus node-via and way-via prohibited/only restrictions.
Conditional restriction text is retained but conservatively treated as active
until the runtime can evaluate its schedule or vehicle expression.

Route planning uses a downloaded graph only when every waypoint is covered by
the same installed pack. Missing coverage, failed snapping, disconnected roads
or invalid packs fall back to the replaceable MapKit provider. Cross-pack
routing and in-ride rerouting both use the local provider within one installed
pack. Cross-pack routing and production-pack physical-device performance
validation remain later milestones.

Account -> Offline Maps exposes private routing diagnostics only inside Download
Settings: aggregate local route and fallback counts, last pack version, last
fallback reason and calculation duration. This data is stored only on-device
and can be reset by the rider; no coordinates or route geometry are retained.

## Release workflow

The `offline-graph-release` GitHub Environment should require approval and hold:

- `OFFLINE_MANIFEST_SIGNING_KEY`: base64 raw 32-byte Ed25519 private key;
- `SUPABASE_S3_ACCESS_KEY_ID` and `SUPABASE_S3_SECRET_ACCESS_KEY`.

The project-specific Storage endpoint and region are non-secret workflow
configuration. If the Supabase project or region changes, update them in the
workflow alongside the public download URL used by the iOS app.

The private signing key and S3 credentials are server-only and must never enter
the repository or iOS bundle. The workflow tests the compiler, downloads the
configured OSM extract, creates a reference-complete regional extract, builds
the pack, audits it, signs and verifies the catalog, retains CI artifacts,
uploads the immutable pack, then publishes `manifest.json` last.

The release-blocking audit validates archive metadata, nodes, directed edges
and turn-restriction references. It measures compression, parse/index time,
peak memory, inflated size, road-class mix, surface coverage and weakly
connected components.
Each region also defines named road probes and directed route pairs. Auckland's
first release must snap and route in both directions between representative
mainland locations around Albany, Orewa, Warkworth and Matakana. The first pack
is deliberately bounded to the North Shore and northeast coast so its decoded
graph remains suitable for phone memory. The JSON quality report is retained
even when the release is rejected.

The first scoped Auckland build contains about 146,000 nodes and 266,000
directed edges. Its 6.2 MB archive inflates to about 70 MB; a release-build
Foundation decode plus component, restriction and routing indexes completed in
about 1.9 seconds with a 352 MiB peak resident set on the build Mac. The release
gate caps this format at 10 MB compressed and 80 MB decoded so a materially
larger JSON graph cannot ship unnoticed. These figures are a baseline for real
device validation, not a guarantee for every iPhone.

Region definitions and version bumps live in
`tools/offline_graph/regions.json`. A changed source or graph contract requires
a new pack version; never overwrite a versioned pack with different bytes.
The workflow can be started manually from the default branch or from an
intentional `offline-graph-nz-auckland-north-v*` release tag. Ordinary branch
pushes never publish packs.

## Release safety

- Keep OSM attribution visible in Offline Areas and route results.
- Publish immutable versioned pack names; update the manifest last.
- Generate SHA-256 after the final pack bytes are written.
- Treat a failed graph audit as a blocked release; inspect its retained report.
- Retain at least one previous manifest and pack version for rollback.
- Keep the prior signed manifest artifact so rollback only requires restoring
  that manifest; immutable older packs remain available.
