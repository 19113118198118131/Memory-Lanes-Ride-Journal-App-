# Memory Lanes Beta Release Preflight

Date: 2026-08-11

## Release Candidate

- Product: Memory Lanes native iPhone app
- Version: 0.1.0
- Build: 1
- Bundle identifier: `app.memorylanes.native`
- Distribution target: internal TestFlight beta

## Blocking Before External TestFlight Or Public Submission

1. **Apply and operate the account deletion workflow.**
   - Implementation: Account now has a deletion-request action, confirmation and immediate sign-out. The companion browser account page has the same action.
   - Remaining release work: apply `supabase-beta-safety-account-deletion.sql`, assign an owner to process the request queue, and confirm the retention and completion policy.

2. **Apply and operate the community safety workflow.**
   - Implementation: non-host group members can report a ride and block its host. The migration stores reports, filters blocked hosts from discovery and removes the blocked rider from that host's memberships.
   - Remaining release work: apply `supabase-beta-safety-account-deletion.sql`, assign a moderation owner and response target, and test report review with a real beta account.

3. **Publish and verify the public trust URLs.**
   - Implementation: `privacy.html`, `terms.html` and `support.html` are included, linked from Account and added to the PWA shell.
   - Remaining release work: deploy them to the production HTTPS host, verify the three URLs in a logged-out browser, then enter the privacy and support URLs in App Store Connect.

4. **App Store Connect authentication is not configured locally.**
   - Evidence: `asc auth doctor` finds no config or usable credential profile.
   - Resolution: enable the Apple account for App Store Connect, then use `asc auth login` or an App Store Connect API key. This is required before the CLI can create the app record, upload a build or manage testers.

## Warnings To Resolve During Internal Beta

1. **Privacy nutrition label needs a deliberate review.**
   - The app processes location, identifiers, ride content and social-riding data. The in-repo privacy manifest currently covers required-reason API declarations, but App Store Connect privacy answers must accurately describe collection, linkage, purpose and third-party processing.

2. **Background modes need physical-device validation.**
   - Location, Bluetooth central and peripheral, and audio are declared. Each must be demonstrated with a reviewer-ready explanation and must have a clear rider benefit. Remove any mode that is not actively necessary for the release build.

3. **Push notification operations are not activated.**
   - The app carries an APNs entitlement while production activation is still listed as release work. Validate a real device and notification credential, or ensure beta copy makes no delivery guarantee.

4. **Offline coverage needs product copy discipline.**
   - Downloaded maps and routing are valid only where an area and road pack are installed. The beta must never imply all-country offline navigation.

## Passed Or Verified

- An unsigned Release archive completed on 2026-08-11. It contains an arm64
  `MemoryLanes.app` with bundle identifier `app.memorylanes.native` and version
  `0.1.0 (1)`. Signing is intentionally blank because this was a packaging
  smoke test, not an upload artifact.
- Native simulator compilation completed successfully after the current Flow,
  replay and interaction work.
- App icon catalog is configured through the generated Xcode project.
- A privacy manifest is present.
- Location, Bluetooth and local-network usage strings are present.
- Portrait and landscape orientations are declared for the iPhone target.
- Root git branch is `main`, and beta source is pushed to `origin/main` at `8618107`.

## Verification Limitation

- The local CoreSimulator service was unavailable during this preflight, so a
  fresh simulator test run could not be executed. Re-run the automated and
  manual simulator checks once the service is healthy. Physical iPhone testing
  remains the higher-value beta gate for location, background recording,
  Bluetooth and offline behavior.
- The web Flow logic suite could not run because `node` is not installed or not
  on this Mac's `PATH`. Install Node 20 or later, then run
  `pnpm run test:flow` from the repository root.

## Internal Tester Charter

Focus the first cohort on real-world reliability, not feature breadth:

1. Recording with screen locked, low battery and intermittent reception.
2. Finish, save, recovery, queued upload and journal appearance.
3. Planned navigation with and without a downloaded area.
4. GPX import, replay scrubber, moments and exports.
5. Private group creation, invitation, RSVP, check-in, announcement and consent boundaries.
6. Ride Mesh in range, out of range and airplane-mode conditions.

## App Store Connect Commands After Authentication

```bash
asc auth login
asc apps list --bundle-id app.memorylanes.native --output table
asc validate --help
asc testflight groups list --app "APP_ID" --paginate
```

Use the `asc` CLI only after the account is enabled for App Store Connect. Internal beta distribution still requires an active Apple Developer Program membership and App Store Connect access.
