# Native UI/UX Audit

Last reviewed: 19 July 2026

## Scope

This pass reviewed the SwiftUI feature and component tree for visual hierarchy,
affordance, loading/empty/error states, progressive disclosure, touch targets,
Dynamic Type structure, reduced motion, semantic tokens, tactile feedback and
route-planning workflow continuity. It included a deeper interaction audit of
the complete route setup, generation, recovery, selection and save flow, plus
the ride-detail replay controls, journal cards, Rider Craft corner tickets and
stats navigation. The Account pass also covers rider identity, community
notifications, local ride storage, offline road packs, data export and session
management.

The review used the native design system and the `make-interfaces-feel-better`
principles. Fixed chart and map dimensions are intentional stable canvases;
arbitrary UI spacing, radii and animation values remain design-system owned.

## Hierarchy and disclosure

| Before | After |
| --- | --- |
| Plan and refresh actions competed at the same visual weight. | Route planning has one dominant full-width action; saved-route refresh is contextual to its section. |
| A planner failure appeared below unrelated group-ride content. | Loading, success and failure feedback appears directly beneath the action that caused it. |
| Candidate cards exposed every scoring reason by default. | A plain-language route label and score lead; technical reasons and personalisation evidence expand on demand. |
| Custom settings had no visible escape hatch. | `Reset options` appears only when the setup differs from defaults and is repeated in the no-result recovery state. |
| Account community identity and notifications appeared as separate single-row sections. | Related rider and community controls share one scannable group with one privacy explanation. |
| The Account overview repeated cloud sync while offline road packs were buried below the fold. | The third overview metric now reports installed offline areas; the destination also shows local storage and readiness. |

## Feedback and workflow safety

| Before | After |
| --- | --- |
| Option changes could leave stale results or errors on screen. | Any start or parameter change cancels the active generation and clears obsolete state. |
| A late async result could replace a newer setup. | Generation revisions prevent cancelled or stale tasks from publishing candidates. |
| Current-location and start-search failures could remain ambiguous or loading indefinitely. | Location shows explicit progress; all search paths settle into selected, empty or actionable error states. |
| Save errors were detached blocks in the page flow. | Save failures use the shared toast system and retain the candidate for another attempt. |
| MapKit throttling surfaced as inconsistent generic failures. | A rolling request gate stops before throttling and explains when the rider should retry. |
| `arrow.down.map` was not a valid SF Symbol, leaving Offline Areas and its empty state with blank icon slots. | Both states use the valid `map.fill` symbol and retain explicit text labels. |
| Account export used a chevron even though it performs an action rather than navigating. | A trailing accent `Export` label communicates the command and changes to an inline progress state while working. |
| Downloaded-area status stayed stale after returning from Offline Areas. | Account refreshes local pack count and storage whenever it becomes visible again. |

## Touch, motion and typography

| Before | After |
| --- | --- |
| Several cards used custom `0.98` or `0.985` press scales. | Interactive surfaces use the shared `0.96` physical press response throughout. |
| Small search, disclosure and tier controls had inconsistent hit areas. | Route-planning controls provide at least 44-point touch targets. |
| Some changing numeric labels could shift as values changed. | Planner distance, segmented metrics and monthly totals use tabular numerals. |
| Route-specific animations did not all respect Reduce Motion. | Compass selection, disclosure, loading and account transitions honour the system preference. |
| A few feature views contained raw spacing/radius values. | Those values now resolve through semantic spacing and radius tokens. |
| Compact replay, rename and share controls had mixed 36–44 point footprints. | Ride-detail icon actions now use the shared 44-point minimum target and press physics. |
| Remaining journal and craft labels bypassed semantic font roles. | Moment, weather, journal and corner-ticket typography now resolves through `MLFont`; changing metrics use tabular numerals. |

## Adaptive content

| Before | After |
| --- | --- |
| Corner speed progression and four metadata values could compress into a dense horizontal strip at larger text sizes. | Speed progression falls back to a readable vertical sequence and metadata uses an adaptive grid. |
| Journal metadata was forced to one line, which could truncate the date, speed or elevation. | Metadata uses `ViewThatFits` to retain the compact row when it fits and stack without truncation when it does not. |
| Corner cards combined every child into one VoiceOver element, including replay. | The card is now a containing group, preserving replay as an independently reachable action. |
| The full connected-status label could crowd rider identity at larger text sizes. | `ViewThatFits` keeps the readable status pill when space permits and falls back to an accessible icon at constrained widths. |

## Surface quality

| Before | After |
| --- | --- |
| Route thumbnails shared the same radius as their outer card despite inset padding. | Inner maps use the smaller button radius and a subtle semantic outline. |
| Loading swapped the primary label entirely for a spinner. | The action label stays stable while a compact spinner communicates progress. |
| Route scoring blocks added nested visual weight inside candidate cards. | The score is an unframed disclosure row, reducing surface nesting and visual noise. |
| Journal artwork reused the outer card radius inside an inset surface. | Inset route artwork now uses the smaller button radius for concentric corners. |
| Account rows relied on loose standalone glyphs, making newer destinations harder to scan. | Semantic symbols now sit in restrained tinted icon tiles with aligned dividers and shared press feedback. |

## Project reproducibility

| Before | After |
| --- | --- |
| A regenerated project could produce an unnamed `.app`, omit Debug testability and expose an auto-created scheme without a test action. | `project.yml` now pins product names, Debug optimization/testability, the unit-test bundle loader and a shared build/test scheme. |
| A local generated project retained a stale source reference from another branch. | Regenerating from `project.yml` now gives a clean `main` source graph and a repeatable build. |

Verification on 19 July 2026: unsigned generic-device build succeeded with
Xcode 26.5; all 120 native tests passed on an iPhone 17 Pro iOS 26.5 simulator
with zero failures and zero skips.

## Remaining release validation

| Current evidence | Required before App Store release |
| --- | --- |
| Code-level Dynamic Type layouts use adaptive grids, flexible text and semantic fonts. | Screenshot-test the four primary tabs and route setup at standard, XXXL and accessibility sizes on small and large iPhones. |
| Controls include labels, combined elements and minimum hit targets. | Complete a physical-device VoiceOver pass, including route chips, map actions, charts and recorder controls. |
| Motion is spring-based and major custom transitions respect Reduce Motion. | Profile long map-heavy sessions with Instruments and verify animation frame pacing on the oldest supported device. |
| Deterministic planner tests cover cancellation, reset, diversity, geometry and request limits. | Field-test coastal, rural, dense-city and poor-network starts; retain anonymised failure telemetry before broad release. |
