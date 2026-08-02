# Memory Lanes — Native iOS (SwiftUI)

A ground-up native rewrite of the Memory Lanes ride journal, built to an
Apple/Tesla/Calimoto/Strava quality bar. This directory is the native app; the
repository root still contains the existing Capacitor web app during migration.

## Status

The native app is functional end to end and is being hardened through real-road
testing:

- ✅ **Flow between rides** — the native app bundles the same deterministic,
  offline-capable Canvas experience as the web PWA. Quick Reset and Open Road
  are available before sign-in and from the ride dashboard; game scores remain
  separate from real-world Ride Coach analytics.
- ✅ **Identity and design system** — premium welcome/auth, rider account,
  semantic colour/type/spacing, spring motion, haptics and reusable components.
- ✅ **Ride library** — Supabase sync with an on-device local-first ride index,
  GPX/parsed-track/detail caches, live background recording, recovery, import,
  rename, journal, sharing and export.
- ✅ **Ride intelligence** — replay map, elevation/speed/acceleration/grip
  visualisations, Rider Craft calibration and progress, Ride Coach, corner
  tickets, Limit Point research preview and explainable insights.
- ✅ **Private adaptive analysis** — Rider Craft and Limit Point review labels
  feed versioned Bayesian reliability models stored on-device. Personalisation
  changes confidence language only; raw geometry, detector thresholds and
  safety boundaries remain deterministic. Rider Craft v2 retires the failed
  early-apex GPS proxy without breaking old archives.
- ✅ **Routes and social rides** — saved routes, editing, GPX export, route
  following, planned-vs-actual matching, native invite deep links, private and
  community events, capacity-aware three-state RSVP, attendee privacy, organiser
  dashboard/edit/cancel/complete controls, ride-day check-in and readiness,
  host announcements, shared-route recording, and explicit per-ride live-location
  consent with throttled, expiring group-aware publishing, an independent stop control,
  and fresh named rider markers on the live MapKit cockpit. Joined rides also
  include Ride Mesh: explicitly activated, group-key-encrypted nearby messaging
  over concurrent Bluetooth LE and local Wi-Fi/AWDL transports, with BLE
  fragmentation, quick safety signals, bounded multi-hop relay, duplicate
  suppression and queued delivery when another rider comes into range. The
  matching web lobby
  now supports member check-in and announcements plus a direct iPhone Ride Mesh
  handoff, while explaining that desktop browsers cannot join the nearby radio
  session.
- ✅ **Independent routing Phase 1.5** — MapKit fallback behind a provider seam,
  proprietary route-character scoring, randomized road-validated candidates,
  searchable and recent start locations, primary/secondary mood blends,
  multi-direction departure bias, geometric diversity, and progressively disclosed
  best/close/explore matches with visible time or distance trade-offs. Generation
  retries failed coastal anchors and fresh geometry in bounded rounds, reuses
  validated road legs, stays below Apple Maps request throttling, and offers
  cancellable loading plus nearby retry/reset recovery when no loop is found.
- ✅ **Offline Maps** — riders move and zoom a MapLibre map, download the exact
  highlighted area, monitor or resume progress, open the stored map without
  reception, and rename or remove downloads. One offline-area action now bundles
  the visual map with every published road graph intersecting the selection;
  older downloads can finish setup from their area card, and capability copy
  clearly distinguishes full, partial and map-only coverage.
- ✅ **Offline graph release pipeline** — deterministic motorcycle-access-aware
  OSM compilation, one-way edges, turn restrictions, raw-DEFLATE graph archives,
  SHA-256 pack integrity, Ed25519-signed catalogs and pack-first Supabase S3
  publication with fixture coverage. Releases are blocked on graph integrity,
  component health and representative two-way Auckland route probes, with a
  retained performance and quality report.
- ✅ **Embedded offline routing** — validated DEFLATE graph loading, cached spatial
  indexing, shared-component road snapping, turn-aware A*, one-way and
  turn-restriction enforcement, road/surface scoring context and automatic
  MapKit fallback when one installed region cannot serve the request. Private,
  coordinate-free diagnostics surface local usage, pack version and fallback
  reasons in Offline Areas without sending rider location off-device.
- ✅ **Offline-first turn-by-turn foundation** — installed road packs generate
  conservative named-road maneuvers on-device, with MapKit fallback outside
  downloaded coverage. Planned rides show glanceable instructions, remaining
  distance and ETA, optional spoken prompts, loop-safe monotonic progress,
  arrival handling and sustained offline-first rerouting. A planned ride waits
  for its first real GPS fix before joining the saved route. Navigation failure
  never interrupts recording, remains visible with saved-route guidance and an
  explicit retry action, and does not hammer routing providers on every GPS fix.
  Inside a completed downloaded area the live cockpit renders from the same
  MapLibre offline cache; elsewhere it uses the enhanced Apple Maps surface.
  The live cockpit now defaults to a speed-aware immersive camera, keeps the
  next and following maneuvers in the forward focal area, and reserves the
  compact lower instrument for speed, arrival and distance remaining.
- ✅ **Durable recorded-ride sync** — every completed recording is secured in a
  protected on-device queue before upload. Storage and database writes use one
  stable ride identity, so interrupted retries remain idempotent. Pending rides
  retry on sign-in, foregrounding and restored connectivity, with a compact
  dashboard status and manual retry affordance. “Keep for Later” now genuinely
  queues the ride instead of repeatedly presenting legacy recovery UI.
- 🚧 **Production hardening** — production-hosted vector tiles with an availability
  SLA, broader real-world route coverage, APNs credential activation,
  community moderation, host handover,
  physical-device live-sharing validation, accessibility passes and release telemetry.

The graph-pack client, compiler, signed-release workflow and embedded pathfinder
are now in place. The first scoped Auckland build has passed deterministic
quality, connectivity, route and desktop load benchmarks. Physical-iPhone
validation of downloaded-map rendering and a production vector-tile SLA remain
release work. Cross-pack routing remains a later routing milestone. See
`../docs/independent-routing-architecture.md` and `../docs/offline-region-packs.md`.
The latest static product-quality review is in `../docs/native-ui-ux-audit.md`.

## Requirements

- macOS + Xcode 15+ (iOS 17 SDK)
- [XcodeGen](https://github.com/yonyz/XcodeGen) — `brew install xcodegen`

## Build

```bash
cd ios-native
xcodegen generate          # produces MemoryLanes.xcodeproj from project.yml
open MemoryLanes.xcodeproj  # ⌘R to run, or use the canvas previews
```

Every component and screen has SwiftUI `#Preview`s — open any file in
`Components/` or `Features/` and use the Xcode canvas to see all states
(populated / empty / loading / error) in light and dark without running the app.

> The project is generated from `project.yml` rather than committing a
> hand-maintained `.xcodeproj`, which keeps the repo diff-friendly. Regenerate
> after adding files.

## Layout

```
MemoryLanes/
  App/            MemoryLanesApp (entry), RootView (tab shell)
  DesignSystem/   Theme, Typography, Spacing, Motion, Haptics
  Components/     StatCard, RideCard, Buttons, EmptyState, Toast, …
  Features/       One folder per screen: View + @Observable ViewModel
  Services/       Protocol-first, injectable (RideServing)
  Models/         Ride and value types (Sendable)
  PreviewContent/ Sample data for previews only
  Resources/      Info.plist, assets
```

## Principles

Read `DESIGN-SYSTEM.md` before adding UI. In short: semantic tokens only, no
magic numbers, SF Symbols only, one ViewModel per screen, no force unwraps,
`async/await` throughout, and a component for anything used more than once.
