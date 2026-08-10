# Memory Lanes

Memory Lanes is a motorcycle ride journal for recording, revisiting and reflecting on the roads that matter. It is built around dependable ride capture, calm post-ride storytelling and technique-led insight, not speed competition.

**Ride with presence. Remember the roads that mattered.**

## First Beta

The active beta product is the native SwiftUI iPhone app in [`ios-native/`](ios-native/). The repository root retains the original static web PWA and shared assets while the native product matures.

| Area | What riders can do in beta |
|---|---|
| Record | Capture rides in the background, recover an unfinished recording, import GPX and save to a local-first ride library that syncs with Supabase. |
| Revisit | Replay a ride, scrub through the route, add and edit moments, journal the experience, export GPX and share a ride. |
| Reflect | Explore elevation, speed, acceleration, grip and explainable Rider Craft insights designed around smoothness and consistency. |
| Plan | Generate route candidates, save routes, export GPX, follow a planned route and compare planned versus actual. |
| Coordinate | Create or join private group rides, RSVP, check in, share ride-day updates and opt into live location or nearby Ride Mesh. |
| Stay useful offline | Download map areas and regional road packs for offline map and routing coverage where available. |
| Reset | Launch Flow from a saved ride for a five-minute, parked-only post-ride breathing ritual before journaling. |

Read the complete [product blueprint](docs/product-blueprint.md) and [beta release preflight](docs/beta-release-preflight.md) before inviting testers.

## Product Boundaries

- Coaching, analytics and Limit Point research are GPS-derived reflection, not professional instruction or safety telemetry.
- Offline navigation is limited to installed supported areas. It does not promise universal coverage.
- Ride Mesh is opt-in nearby coordination, not an emergency service or a guaranteed delivery channel.
- Flow is a paced ritual for when safely parked. It does not sense breathing or make medical claims.
- Group riding is currently best suited to small, trusted beta groups. Public-community moderation controls are release work.

## Repository Layout

| Path | Role |
|---|---|
| [`ios-native/`](ios-native/) | Native SwiftUI iPhone application and tests. |
| `index.html`, `dashboard.html`, `journal.html`, `planner.html` | Original static web PWA surfaces. |
| `flow.html`, `flow.js`, `flow-engine.js` | Shared Flow ritual experience bundled by the web PWA and native wrapper. |
| `docs/` | Product decisions, architecture and release documentation. |
| `.design/` | Design reviews and captured visual QA evidence. |

## Native Build

Requirements: macOS, Xcode 15 or later, XcodeGen, and a configured Apple development team for device builds.

```bash
cd ios-native
xcodegen generate
open MemoryLanes.xcodeproj
```

The project is generated from `ios-native/project.yml`. Regenerate after adding source files.

## Internal Beta Readiness

Current native version: `0.1.0 (1)`.

Before uploading to TestFlight:

1. Resolve the blocking items in [`docs/beta-release-preflight.md`](docs/beta-release-preflight.md).
2. Enable the Apple account for App Store Connect and authenticate `asc` using `asc auth login`.
3. Archive a signed Release build in Xcode.
4. Upload it to App Store Connect, add an internal tester group and attach concise What to Test notes.

## Web PWA Development

The root web app is static HTML, CSS and ES modules backed by Supabase. It has no frontend build step.

```bash
pnpm run test:flow
```

Node 20 or later is required for the Flow logic tests. The Supabase anon key is public by design, but Row Level Security must be enabled for every table and storage bucket.

## Data and Safety

- Map data and tiles require their respective attributions.
- Weather data is sourced from Open-Meteo where configured.
- Ride data belongs to the rider. Sharing and live location require explicit consent.
- Always ride within your ability, the conditions and the law.
