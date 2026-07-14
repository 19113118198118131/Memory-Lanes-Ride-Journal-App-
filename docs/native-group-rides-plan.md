# Native Group Rides

Status: Lobby and shared-route coordination implemented; live position mode pending consent and field validation

## Product Shape

A group ride is one planned route, one host, one recoverable invite, and a set of explicit rider responses. It is not a public club feed, leaderboard, or generic chat room.

The native app preserves the original web flow:

- Create a group ride from a saved planned route.
- Set a meeting time and meeting point.
- Share a secret invite that remains compatible with the web lobby.
- Recover every active hosted or joined ride under Routes.
- Review the route, host, meeting details, attendees, and RSVP state.
- Start the shared route through the existing reliable native recorder.
- End the ride as host, invalidating the invite and removing it from member lists.

## Native Information Architecture

Group rides live in the Routes tab because they are scheduled uses of planned routes. Adding a fifth primary tab would dilute the four established repeat workflows and give a still-growing social surface too much permanent weight.

Active group rides appear before route-planning controls so an upcoming commitment is easier to reach than route creation. The lobby remains map-first and reuses the app's established metric, surface, button, loading, error, confirmation, and Dynamic Type patterns.

## Live Location Gate

RSVP does not enable location sharing. Starting the route in this phase records only the rider's own ride through the existing native recorder.

Mutual live positions require a later versioned slice with:

- A separate, explicit sharing control immediately before recording.
- Clear membership and invite-based visibility boundaries.
- Automatic expiry and deletion after the ride.
- Background battery and network testing on real devices.
- Stale-position handling and honest offline states.
- A prominent stop-sharing control that does not stop local ride recording.
- Tests confirming that declining or revoking sharing never blocks the ride.

## Next Slices

1. Native universal-link handling for group invites, including post-auth return to the lobby.
2. Explicit live-position consent and group-aware recording.
3. Mutually visible live rider markers with freshness indicators.
4. Leave-group and host handover rules.
5. Optional post-ride group recap without rankings, pace comparison, or pressure mechanics.
