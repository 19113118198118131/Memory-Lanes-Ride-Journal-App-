# Memory Lanes Product Blueprint

## Product

Memory Lanes is a private motorcycle ride journal that helps riders record, revisit and reflect on rides. It combines dependable background recording, a personal ride library, route planning, replay, coaching and group coordination in one calm, rider-first product.

## Product Pitch

**Ride with presence. Remember the roads that mattered.**

Memory Lanes turns a finished ride into a story: the route, the moments, the road character and the next small thing to practise. It is designed for motorcyclists who value the feeling of a ride as much as the distance covered.

## Who It Is For

- Solo riders who want a dependable record of their rides without managing files.
- Touring and weekend riders who want to revisit routes, moments and conditions.
- Riders who want calm, technique-led reflection instead of speed competition.
- Small groups that need lightweight planning, RSVPs, ride-day coordination and optional nearby messaging.

## Core Jobs

| Rider job | Memory Lanes outcome |
|---|---|
| Record a ride safely while the phone is locked | Background GPS recording, recovery and durable upload queue protect the track. |
| Remember why a road or stop mattered | Ride replay, moments, journal entries and sharing keep the context. |
| Understand a ride without turning it into a race | Explainable analytics and Rider Craft reward smoothness, consistency and reflection. |
| Find a ride that fits the time and mood available | Route planner offers a bounded set of road-character candidates and saved routes. |
| Coordinate a group ride without a noisy social network | Private rides, RSVP, check-in, organiser updates and opt-in live sharing. |
| Keep going when reception is poor | Downloaded map areas, offline routing coverage and Ride Mesh where available. |

## Experience Principles

1. **Ride first.** Recording and navigation must remain glanceable, reliable and quiet.
2. **Reflection, not competition.** No feature rewards risky speed, lean or comparison with strangers.
3. **Local first, cloud when useful.** The rider should see their library quickly and recover gracefully from poor reception.
4. **Consent is explicit.** Live location, nearby radio communication and sharing are opt-in and easy to stop.
5. **Explain the evidence.** Coaching language must describe GPS-derived signals as approximate and never overstate certainty.
6. **Premium through restraint.** Clear hierarchy, generous space, purposeful glass, and motion that supports orientation.

## Product Surfaces

| Surface | Beta scope | Value |
|---|---|---|
| Ride home | Dashboard, local ride index, import and start recording | Fast entry to the rider's current journey. |
| Live ride | Background recording, map cockpit, optional planned-route guidance | Dependable capture with minimal distraction. |
| Ride story | Replay, telemetry, moments, journal and sharing | Make a route feel memorable after the ride. |
| Ride intelligence | Elevation, speed, acceleration, grip, Rider Craft and Limit Point research views | Provide calm, explainable reflection. |
| Routes | Planner, saved routes, GPX export and route following | Help riders choose and carry a route. |
| Community | Private and community group rides, RSVP, check-in, announcements and Ride Mesh | Coordinate small groups with consent. |
| Offline | Downloaded map areas and regional road packs | Preserve map and routing usefulness outside reception. |
| Flow | Five-minute post-ride breathing ritual from a saved ride | Create a deliberate bridge from riding to journaling. |

## Beta Scope

### In This Beta

- Native iPhone ride recording, GPX import, ride save, local cache and Supabase sync.
- Ride detail, cinematic replay, editable moments, journal, analytics and Rider Craft.
- Route planning, saved routes, turn-by-turn foundation and planned-versus-actual comparison.
- Offline map areas and installed road-pack routing where coverage exists.
- Group ride planning, RSVP, organiser tools, opt-in location sharing and Ride Mesh.
- Flow as a post-ride ritual with local-only self reports.

### Explicit Beta Boundaries

- Offline routing is regional. Cross-region routing and universal map coverage are not yet promised.
- Ride Mesh is a nearby, opt-in coordination aid, not an emergency or guaranteed delivery system.
- Analytics and Rider Craft are GPS-derived reflection, not professional instruction or safety telemetry.
- Limit Point Analysis is research-only and must not be used for live riding decisions.
- Flow is a paced ritual for when parked safely. It is not a medical feature or a breathing sensor.
- Community reporting and host blocking are available in beta. Reports require an operational review process before broader community expansion.

## Beta Success Criteria

- A rider can record a real ride, lock the phone, finish, save and find it in the journal.
- A rider can import a GPX, replay it, add and edit a moment, and share an export.
- A rider can download a supported area, view it without reception and follow a saved route where road-pack coverage exists.
- A host can create a private group ride and invited riders can RSVP, check in and receive updates.
- Every permission is requested in context and every sensitive feature can be stopped or exited clearly.
- Internal testers can describe bugs with a reproducible path, device, iOS version, network condition and ride type.

## Release Sequence

1. Internal TestFlight: recording reliability, offline areas, route guidance, replay and group-ride flows.
2. Apply the beta safety migration, assign report and deletion-request owners, and validate physical-device edge cases.
3. Publish the public support, privacy and terms pages, then complete App Store Connect privacy answers.
4. Expand TestFlight only after the safety and privacy review is complete.
5. Prepare public App Store submission after production coverage, moderation and support operations are live.
