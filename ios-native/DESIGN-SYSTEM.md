# Memory Lanes — Native Design System

The single source of truth for how the native SwiftUI app looks and moves.
Reference bar: Apple native apps, Tesla, Calimoto, Strava. Every screen is
assembled from library components — no one-off styling. If you need something
new, add it to the library first.

> **Rule of the system:** screens ask for *semantic tokens* (`Color.mlAccent`,
> `Spacing.md`, `MLFont.display`), never raw values. Raw hex / point numbers live
> only inside `DesignSystem/`.

---

## Color — `DesignSystem/Theme.swift`

Dark-first, true-dark identity (the app forces `.dark`).

| Token | Dark | Role |
|---|---|---|
| `mlBackground` | `#0A0A0A` | App background — true dark, not navy, not grey |
| `mlSurface` | `#141414` | Cards, sheets — one step up |
| `mlSurfaceElevated` | `#1C1C1C` | Modals, popovers, top layer |
| `mlHairline` | `#2A2A2A` | Borders, separators |
| `mlAccent` | `#2EE6C0` | The **one** accent (cyan/mint) — used sparingly |
| `mlTextPrimary` | `#F5F5F7` | Headings, values (AA on `#0A0A0A`) |
| `mlTextSecondary` | `#9A9AA0` | Labels, metadata |
| `mlTextTertiary` | `#6A6A70` | Kickers, axis labels |
| `mlSuccess / mlWarning / mlDanger / mlInfo` | semantic | Feedback only — never decorative |

Light mode is defined for completeness (adaptive `UIColor`), but the product
identity is dark. All text roles meet WCAG AA on their intended surface.

## Typography — `DesignSystem/Typography.swift`

SF Pro (system). Every role is anchored to a Dynamic Type `TextStyle`, so text
scales with accessibility settings. **Never more than 3 sizes on one screen.**

| Role | Face | Use |
|---|---|---|
| `displayXL` / `display` / `displaySmall` | SF Rounded, Heavy/Bold | Hero numbers, ride stats |
| `title` / `title2` | SF Pro, Bold/Semibold | Screen + card titles |
| `headline` | SF Pro, Semibold | Buttons, prominent rows |
| `body` / `callout` | SF Pro Text | Reading text, labels |
| `caption` / `kicker` | SF Pro Text | Metadata, uppercase eyebrows |
| `mono` / `monoSmall` | SF Mono | GPS coords, technical values |

Helpers: `.mlKicker()`, `.mlCaption()`.

## Spacing — `DesignSystem/Spacing.swift`

Base unit **4pt**. No magic numbers in views.

`xxs 4 · xs 8 · sm 12 · md 16 · screenH 20 · lg 24 · xl 32 · xxl 48`

- Screen horizontal margin is always `Spacing.screenH` (20pt) via `.mlScreenPadding()`.
- Minimum touch target 44×44pt via `.mlHitTarget()`.

## Corner radius — `DesignSystem/Spacing.swift`

`Radius.card 16 · Radius.button 12 · Radius.chip 8 · Radius.pill 999`
Never mix radius values on the same surface.

## Iconography

SF Symbols exclusively, weight matched to adjacent text. Icons are sized by the
font system, never scaled manually.

## Motion — `DesignSystem/Motion.swift`

- Interactive spring: `Motion.spring` → `.spring(response: 0.4, dampingFraction: 0.75)`.
- Every custom button uses `.buttonStyle(.mlPressable)` for a shared press-scale.
- Transitions slide/fade, never bounce. Loading uses **skeletons** (`mlShimmer`),
  never a spinner over content.

## Haptics — `DesignSystem/Haptics.swift`

Semantic call sites: `Haptics.selection()` (light, on tap), `Haptics.impact(.medium)`
(commit an action), `Haptics.success()` / `.warning()` / `.error()` (notifications).

---

## Component library — `Components/`

Each has `#Preview`s covering its states (populated / empty / loading / error / light+dark).

| Component | File | Notes |
|---|---|---|
| StatCard | `StatCard.swift` | Label, big value, unit, optional trend |
| RideCard | `RideCard.swift` | Route thumbnail, title, 3 stats, source badge, flow chip |
| SectionHeader | `SectionHeader.swift` | Title + right-aligned action |
| SegmentedMetric | `SectionHeader.swift` | 3–4 stats with hairline dividers |
| PrimaryButton / SecondaryButton / DestructiveButton | `Buttons.swift` | Pill, haptics, built-in loading; destructive confirms first |
| EmptyState | `EmptyState.swift` | Icon, title, body, optional CTA |
| SkeletonLoader | `SkeletonLoader.swift` | Shimmer bars + `RideCardSkeleton` |
| Toast | `Toast.swift` | Bottom, auto-dismiss, success/error/info; `.mlToast($toast)` |
| BottomSheet | `BottomSheet.swift` | Native detents, drag handle; `.mlBottomSheet(...)` |
| MapView / RouteThumbnail | `MapView.swift` | MapKit, accent polyline, gradient fade |
| ElevationChart | `ElevationChart.swift` | Swift Charts area chart, scrub gesture, AX descriptor |

---

## Architecture

- SwiftUI + `@Observable` (iOS 17+), one `@MainActor` ViewModel per screen.
- Services are protocol-first and injected (`RideServing`) — no globals, testable.
- `async/await` throughout, `SWIFT_STRICT_CONCURRENCY: complete`.
- Lists use `LazyVStack`; no force unwraps; SF Symbols only.

See `README.md` for how to generate and build the project.
