# Native Group Rides

Status: Production event and ride-day coordination implemented; notification preferences, local reminders and secure APNs outbox implemented; APNs credentials and explicit live position mode pending activation/field validation

## Product Shape

A group ride is one planned route, one host, one recoverable invite, and a set of explicit rider responses. It is not a public club feed, leaderboard, or generic chat room.

The native app preserves the original web flow:

- Create a group ride from a saved planned route.
- Set a description, meeting time, meeting point, visibility, and optional capacity.
- Share a web-compatible invite with a native app handoff. Release builds support
  universal links; Personal Team debug builds use the lobby's custom app-link action.
- Recover every active hosted or joined ride under Routes.
- Discover opt-in community rides without exposing invite-only events.
- Review the route, host, meeting details, capacity, attendees, and RSVP state.
- Respond Riding, Maybe, or Not this time, with capacity enforced on the server.
- Leave a joined ride, or edit, cancel, and complete a hosted ride.
- Check in during the six-hour pre-ride to twelve-hour post-start window, with a
  reversible arrival state that remains separate from RSVP and location sharing.
- Use the organiser dashboard to monitor arrivals, Riding, Maybe, and Declined responses.
- Post concise host updates to the lobby and queue them for opted-in riders.
- Start the shared route through the existing reliable native recorder.
- Refresh event state manually or through a quiet foreground observer.
- Choose event, RSVP, reminder, and quiet-hour notification preferences in Account.
- Receive a native reminder before an accepted or tentative ride; notification taps
  deep-link directly to the matching lobby.

## Native Information Architecture

Group rides live in the Routes tab because they are scheduled uses of planned routes. Adding a fifth primary tab would dilute the four established repeat workflows and give a still-growing social surface too much permanent weight.

Upcoming commitments and discoverable community rides appear before route-planning controls. Community results use progressive disclosure so social discovery does not overwhelm the core route workflow. The lobby remains map-first and reuses the app's established metric, surface, button, loading, error, confirmation, motion, and Dynamic Type patterns. Ride-day operations disclose only when useful: the latest host update appears first, older updates expand on demand, and organiser readiness replaces a second RSVP control for hosts.

## Privacy And Access

- Invite-only rides never appear in community discovery.
- Community discovery requires a signed-in rider.
- Holding a secret invite can reveal the event and route, but attendee names require host or member access.
- Event mutations, personal lists, community discovery, and live-rider reads require authentication.
- Capacity is enforced inside the RSVP database function, not only in the UI.
- Check-in and host announcement mutations are authenticated, time/role gated RPCs;
  clients cannot read or write the underlying announcements table directly.
- RSVP does not enable location sharing.

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

1. Activate APNs credentials and the one-minute worker scheduler on the paid Apple team.
2. Explicit live-position consent and group-aware recording.
3. Mutually visible live rider markers with freshness indicators.
4. Host handover plus moderation, report, and block rules before a broader rider directory or messaging surface.
5. Optional post-ride group recap without rankings, pace comparison, or pressure mechanics.
