# Memory Lanes Beta Release Preflight

Date: 2026-08-11

## Release Candidate

- Product: Memory Lanes native iPhone app
- Version: 0.1.0
- Build: 1
- Bundle identifier: `app.memorylanes.native`
- Distribution target: internal TestFlight beta

## Blocking Before External TestFlight Or Public Submission

1. **Account deletion is not available in-app.**
   - Evidence: the native app can sign out, but has no self-service account deletion flow.
   - Why it matters: App Review Guideline 5.1.1 requires apps that support account creation to initiate deletion within the app.
   - Resolution: add an Account deletion action, confirmation, backend delete endpoint or Supabase function, and a documented retention policy.

2. **Community safety controls are incomplete.**
   - Evidence: group rides and announcements exist, but there is no report, block or moderation workflow in the native app.
   - Why it matters: user-generated or social content requires a reporting mechanism, blocking capability and a way to contact the developer.
   - Resolution: add report and block flows, moderation handling, terms, escalation process and support contact before inviting untrusted external users.

3. **Public support and privacy URLs are not defined.**
   - Evidence: no privacy policy, terms or support surface is included in the repository.
   - Why it matters: App Store Connect requires a privacy policy URL. Support information is required for a credible public release.
   - Resolution: publish accessible HTTPS Privacy Policy, Terms of Use and Support pages, then enter the URLs in App Store Connect and link them from Account.

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
