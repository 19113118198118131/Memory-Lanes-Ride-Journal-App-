# Memory Lanes — Native iOS (SwiftUI)

A ground-up native rewrite of the Memory Lanes ride journal, built to an
Apple/Tesla/Calimoto/Strava quality bar. This directory is the native app; the
repository root still contains the existing Capacitor web app during migration.

## Status

Building in the order the brief mandates:

- ✅ **Design system** — colour, typography, spacing, radius, motion, haptics
  (`DesignSystem/`, documented in `DESIGN-SYSTEM.md`).
- ✅ **Component library** — reusable components with `#Preview`s for every
  state (`Components/`): the original 13 plus segmented control, corner ticket,
  moment row, weather strip, and an exportable share card.
- 🚧 **Screens** — Dashboard (ride list) and **Ride Detail** (hero map,
  stats-over-map, interactive elevation chart, corners/moments/weather sections,
  one-tap share) rebuilt from the library. Upload/Import, Analytics, Journal,
  Planner next.
- ⬜ **Services** — Supabase-backed `RideService` (protocol + stub in place),
  GPX parser, Strava import.

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
