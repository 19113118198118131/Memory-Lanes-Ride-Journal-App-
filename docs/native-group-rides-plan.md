# Native Group Rides

Status: Production event and ride-day coordination implemented; notification preferences, local reminders and secure APNs outbox implemented; explicit live-position consent, group-aware publishing, and fresh rider markers implemented pending production migration and physical-device validation; APNs credentials pending activation

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
- Live sharing starts only after a separate per-ride toggle that defaults off.
- Only the host and riders marked Riding can publish or read group positions.
- Stopping sharing does not stop local recording; failed updates leave recording untouched.
- Positions become unreadable two minutes after updates stop, and consent has a hard
  ride-window expiry even when the app is force-quit.

## Live Location Gate

RSVP does not enable location sharing. The native start sheet now asks separately on
every group ride and defaults to private. When enabled, the recorder publishes a
throttled position through authenticated RPCs and exposes a persistent stop control.
Network or consent failures are honest but non-blocking: the local ride and GPX continue.
Fresh positions from other participating riders appear as named MapKit markers. Riders
who keep their own location private can still record the shared route and see positions
that others explicitly chose to share. Stale markers are removed after two minutes.

The production migration in `supabase-group-live-sharing.sql` adds consent audit rows,
role-gated publishing, two-minute position expiry, opportunistic cleanup and hardened
direct-write policies. It must be applied before enabling the client on a release build.

Physical-device validation still requires:

- Background battery and network testing on real devices.
- Weak-signal, pause, force-quit and membership-revocation exercises.
- Confirmation that ten-second publishing remains acceptable on representative rides.

## Next Slices

1. Activate APNs credentials and the one-minute worker scheduler on the paid Apple team.
2. Apply and field-validate explicit live-position consent and group-aware recording.
3. Host handover plus moderation, report, and block rules before a broader rider directory or messaging surface.
4. Optional post-ride group recap without rankings, pace comparison, or pressure mechanics.
