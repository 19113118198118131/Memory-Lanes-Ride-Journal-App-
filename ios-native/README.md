# Memory Lanes — Native iOS (SwiftUI)

A ground-up native rewrite of the Memory Lanes ride journal, built to an
Apple/Tesla/Calimoto/Strava quality bar. This directory is the native app; the
repository root still contains the existing Capacitor web app during migration.

## Status

The native app is functional end to end and is being hardened through real-road
testing:

- ✅ **Identity and design system** — premium welcome/auth, rider account,
  semantic colour/type/spacing, spring motion, haptics and reusable components.
- ✅ **Ride library** — Supabase sync with an on-device local-first ride index,
  GPX/parsed-track/detail caches, live background recording, recovery, import,
  rename, journal, sharing and export.
- ✅ **Ride intelligence** — replay map, elevation/speed/acceleration/grip
  visualisations, Rider Craft calibration and progress, Ride Coach, corner
  tickets, Limit Point research preview and explainable insights.
- ✅ **Routes and social rides** — saved routes, editing, GPX export, route
  following, planned-vs-actual matching, native invite deep links, private and
  community events, capacity-aware three-state RSVP, attendee privacy, organiser
  dashboard/edit/cancel/complete controls, ride-day check-in and readiness,
  host announcements, and shared-route recording.
- ✅ **Independent routing Phase 1.5** — MapKit fallback behind a provider seam,
  proprietary route-character scoring, randomized road-validated candidates,
  searchable and recent start locations, primary/secondary mood blends,
  multi-direction departure bias, geometric diversity, and progressively disclosed
  best/close/explore matches with visible time or distance trade-offs. Generation
  retries failed coastal anchors and fresh geometry in bounded rounds, reuses
  validated road legs, stays below Apple Maps request throttling, and offers
  cancellable loading plus nearby retry/reset recovery when no loop is found.
- ✅ **Offline Areas foundation** — rider-selected map regions in Account,
  verified and atomically activated road-graph downloads, Wi-Fi controls,
  updates, storage management, cached catalog fallback and a coverage lookup
  seam for the embedded routing provider.
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
- 🚧 **Production hardening** — broader real-world route coverage, offline upload
  queue, APNs credential activation, community moderation, explicit live-location
  consent, accessibility passes and release telemetry.

The graph-pack client, compiler, signed-release workflow and embedded pathfinder
are now in place. The first scoped Auckland build has passed deterministic
quality, connectivity, route and desktop load benchmarks; publishing it and
validating on physical iPhones are the remaining release steps. Cross-pack
routing, offline rerouting and turn-by-turn navigation remain later routing
milestones. See
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
