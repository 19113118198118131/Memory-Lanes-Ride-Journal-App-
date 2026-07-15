# Offline Region Packs

## Product contract

Riders manage downloaded road coverage from **Account → Offline Areas**. The
map selector resolves its visible bounds against the published catalog and
downloads intersecting packs. MapKit remains the online fallback until an
installed graph covers the planning start.

The first release downloads routing data only. Apple Maps remains the visual
basemap while online. Offline raster/vector tiles can be layered in a later
navigation phase without changing the graph-pack lifecycle.

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
  "keyID": "release-2026-01",
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
      "detail": "Albany, Hibiscus Coast and Warkworth",
      "bounds": {
        "south": -36.86,
        "west": 174.54,
        "north": -36.25,
        "east": 175.08
      },
      "version": 1,
      "formatVersion": 1,
      "encoding": "zlib-json",
      "byteCount": 48382910,
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

`.mlgraph` is deterministic zlib-compressed canonical JSON matching
`OfflineRoadGraphArchive`:

- directed nodes and edges suitable for one-way and turn-aware expansion;
- distance and expected travel time per edge;
- OSM way ID, road class, surface, optional road name and posted maximum speed;
- node-via and way-via prohibited or only-turn restrictions, retaining raw
  conditional text for conservative runtime evaluation;
- region bounds, generation timestamp and OSM attribution.

`tools/offline_graph/build_graph.py` excludes unsupported road classes,
construction geometry, private access, motorcycle prohibitions and ferry paths;
it preserves explicit motorcycle overrides, one-way direction and supported
OSM turn restrictions.

The native app inflates and validates an activated pack off the main actor,
builds a coarse spatial index, snaps planning points to nearby graph nodes and
runs a turn-aware A* search optimized for expected travel time. The search
enforces directed edges plus node-via and way-via prohibited/only restrictions.
Conditional restriction text is retained but conservatively treated as active
until the runtime can evaluate its schedule or vehicle expression.

Route planning uses a downloaded graph only when every waypoint is covered by
the same installed pack. Missing coverage, failed snapping, disconnected roads
or invalid packs fall back to the replaceable MapKit provider. Cross-pack
routing, offline in-ride rerouting and production-pack performance validation
remain later milestones.

## Release workflow

The `offline-graph-release` GitHub Environment should require approval and hold:

- `OFFLINE_MANIFEST_SIGNING_KEY`: base64 raw 32-byte Ed25519 private key;
- `SUPABASE_S3_ACCESS_KEY_ID` and `SUPABASE_S3_SECRET_ACCESS_KEY`;
- `SUPABASE_S3_ENDPOINT`: the direct project Storage S3 endpoint;
- `SUPABASE_S3_REGION`: the Storage region.

The private signing key and S3 credentials are server-only and must never enter
the repository or iOS bundle. The workflow tests the compiler, downloads the
configured OSM extract, creates a reference-complete regional extract, builds
the pack, audits it, signs and verifies the catalog, retains CI artifacts,
uploads the immutable pack, then publishes `manifest.json` last.

The release-blocking audit validates archive metadata, nodes, directed edges
and turn-restriction references. It measures compression, parse/index time,
peak memory, road-class mix, surface coverage and weakly connected components.
Each region also defines named road probes and directed route pairs. Auckland's
first release must snap and route in both directions between representative
mainland locations around Albany, Orewa, Warkworth, Matakana, Helensville and
Kumeu. The JSON quality report is retained even when the release is rejected.

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
