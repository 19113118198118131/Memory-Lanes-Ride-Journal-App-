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

Run `supabase-offline-regions-setup.sql` once, then publish packs through the
Supabase dashboard or trusted release infrastructure. The iOS client has no
write policy.

## Manifest schema

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
      "byteCount": 48382910,
      "sha256": "<64-character lowercase SHA-256>",
      "downloadPath": "packs/nz-auckland-north-v1.mlgraph",
      "updatedAt": "2026-07-15T08:00:00Z"
    }
  ]
}
```

The client rejects duplicate IDs, unsafe paths, unsupported versions, invalid
bounds, size mismatches and checksum mismatches. Downloads are staged and only
replace an installed pack after verification succeeds.

## Graph format v1

`.mlgraph` is a binary property-list encoding of `OfflineRoadGraphArchive`:

- directed nodes and edges suitable for one-way and turn-aware expansion;
- distance and expected travel time per edge;
- road class, surface and optional road name;
- region bounds, generation timestamp and OSM attribution.

The graph builder must enforce legal motorcycle access and preserve OSM turn
restrictions before publication. The next phase adds spatial indexing and an
embedded route provider over this stable archive contract.

## Release safety

- Keep OSM attribution visible in Offline Areas and route results.
- Publish immutable versioned pack names; update the manifest last.
- Generate SHA-256 after the final pack bytes are written.
- Retain at least one previous manifest and pack version for rollback.
- Sign the manifest before broad production release; pack checksums currently
  protect integrity once the trusted HTTPS manifest is retrieved.
