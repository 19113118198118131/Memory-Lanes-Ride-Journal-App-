# Memory Lanes Product UI Audit

## Direction

Memory Lanes should feel calm, capable, and motorcycle-specific. The interface prioritises the next rider action, keeps analysis progressively disclosed, and reserves teal for state and intent rather than decoration.

## Debt Register

| Area | Finding | Severity | Remediation |
| --- | --- | --- | --- |
| Foundations | Four overlapping web token generations define different surfaces, radii, and accent aliases. | High | Add one final semantic compatibility layer and migrate feature CSS into it over time. |
| Navigation | Desktop labels and mobile labels use different information architecture, while several pages render two headers. | High | Use compact desktop chrome and a stable four-destination mobile tab bar. Keep page titles in content. |
| Surfaces | Card radii range from 8 to 32 pixels and several pages use decorative gradients for ordinary content. | Medium | Standardise functional cards and controls to 8 pixels. Keep circles and the floating tab bar as deliberate exceptions. |
| Interaction | Legacy rules include broad transitions and inconsistent focus treatment. | High | Animate only transform, opacity, color, background, and border. Add a shared visible focus ring and 44 pixel targets. |
| Typography | Older pages mix display sizes, tracked labels, inline styles, and non-tabular metrics. | Medium | Use a compact semantic hierarchy, balanced headings, pretty body wrapping, and tabular numerals. |
| States | Loading, empty, and error states vary by page and sometimes appear as raw text. | Medium | Apply one readable state container and preserve page-specific recovery actions. |
| Flow integration | Dashboard copy describes the retired game concept rather than the five-minute ritual. | High | Reframe Flow as a post-ride ritual and keep the launcher secondary to recording. |
| Native parity | SwiftUI is substantially more coherent than web and already follows semantic tokens and spring motion. | Low | Preserve the native system. Use it as the reference during gradual web cleanup. |

## Workflow Review

| Workflow | Primary action | Secondary path | UX requirement |
| --- | --- | --- | --- |
| Start a ride | Start Ride | Import GPX | Primary action must remain the strongest element on the dashboard. |
| Review a ride | Open recent ride | Journal, analytics, craft | Keep one overview first, then disclose technical depth through tabs. |
| Plan a route | Generate candidates | Group and community rides | Keep setup controls ahead of results and explain relaxed matches rather than failing silently. |
| Join a group ride | RSVP | Ride Mesh and updates | State, eligibility, and organiser actions must remain visible without competing cards. |
| Settle after riding | Flow | Journal this ride | Flow is a quiet post-ride transition, never a score or performance surface. |
| Manage account | Profile and data | Offline maps, privacy, sign out | Group rows by rider intent and keep destructive actions isolated. |

## Acceptance Checks

- Primary actions are visually distinct and reachable with one thumb.
- All controls expose at least a 44 by 44 pixel hit area.
- Keyboard focus is visible.
- Dynamic metrics use tabular numerals.
- Mobile pages do not show duplicate top navigation.
- The bottom bar does not cover final content.
- Cards are used for discrete objects, not to frame entire page sections.
- Motion is limited to transform, opacity, and state color changes.
- Reduced-motion mode remains fully usable.
