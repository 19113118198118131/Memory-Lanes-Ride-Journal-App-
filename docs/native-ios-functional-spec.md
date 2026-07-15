# Memory Lanes Native iOS Functional Spec

Version: 2026-07-14
Target app: Native SwiftUI iOS app in `ios-native/`
Source product: Existing Memory Lanes web/Capacitor app at repository root

## 1. Product Definition

Memory Lanes is a premium motorcycle ride journal. Riders record or upload GPS rides, replay them on a map, receive technique-focused coaching, save personal ride memories, plan future routes, and share polished ride artifacts.

The native iOS app should preserve the full original feature set while feeling like a first-class iPhone app rather than a wrapped website.

Primary promise:

- Record or import a ride.
- Replay and understand it.
- Capture the memories.
- Improve smoothly and safely.
- Plan and follow the next ride.

Design principle:

Scores and coaching must reward smoothness, consistency, and technique. The app must never encourage unsafe speed, illegal riding, or aggressive lean-angle chasing.

## 2. Target Users

### 2.1 Solo Rider

Uses the app to record weekend rides, replay routes, remember good moments, and track personal improvement.

### 2.2 Improving Rider

Wants feedback on corner entry, exit drive, braking consistency, and route rhythm without needing race telemetry.

### 2.3 Route Explorer

Plans scenic loops, exports GPX, follows planned routes, and compares planned vs actual ride.

### 2.4 Social Rider

Shares ride cards, public read-only ride links, and optionally rides with a small group.

## 3. Native App Information Architecture

The native app should keep the tab structure already started:

1. Ride
2. Routes
3. Journal
4. Stats

Recommended secondary surfaces:

- Ride Detail
- Live Recording
- Planned Route Detail
- Route Builder
- Import GPX
- Share Preview
- Settings
- Account/Auth
- Data Export

## 4. Feature Inventory

### 4.1 Account and Session

Functional requirements:

- User can sign up, sign in, sign out, and restore session.
- User data is private by default.
- Supabase Row Level Security remains the source of data protection.
- User can reset password.
- App should clearly handle offline, expired session, and network failure states.

Acceptance criteria:

- A signed-out user cannot access private ride data.
- A signed-in user only sees their own rides, routes, moments, and stats.
- Session persists across app restarts.
- Password reset works through a secure flow.

Native implementation notes:

- Use Supabase Swift SDK or a thin HTTP client if SDK fit is poor.
- Store session securely in Keychain.
- Keep service protocols injectable for previews and tests.

### 4.2 Dashboard / Ride Home

Functional requirements:

- Show weekly distance, ride count, best flow score, and recent rides.
- Show loading, empty, failed, and populated states.
- Start live ride recording.
- Import GPX.
- Open ride detail.
- Filter/sort rides by date, distance, source, and skill score.
- Delete a ride with confirmation.

Acceptance criteria:

- New user sees an inspiring empty state with "Start Ride" and "Import GPX".
- Recent rides show title, date, location, distance, duration, elevation, source, and flow score where available.
- Pull-to-refresh reloads rides.
- Deleting a ride removes database row and associated GPX/storage files.

Current native status:

- Dashboard shell exists.
- Ride list uses sample service.
- Start Ride opens a native demo recorder.
- Supabase-backed live service still required.

### 4.3 Live Ride Recording

Functional requirements:

- User starts recording intentionally.
- App requests location permission with clear copy.
- App records GPS points while active and while screen is locked, using native Core Location.
- App shows live timer, distance, current speed, average speed, elevation estimate, GPS quality, and route line.
- User can pause/resume.
- User can add up to five moments during a ride with note and optional photo later.
- User can finish, discard, or save.
- Completed recording becomes a normal ride log.
- If app is killed or crashes during recording, app offers recovery on next launch.

Background requirements:

- Use Always location permission only when user starts a recording.
- Use iOS background location capability.
- Persist points to disk continuously during recording.
- Do not depend on background JavaScript timers.

Acceptance criteria:

- Locking the iPhone does not lose the route during an active ride.
- A recovered ride includes points recorded before interruption.
- Finish generates GPX and ride summary.
- Pause excludes paused time from moving time and prevents duplicate low-quality points.
- User can discard unsaved ride safely.

Current native status:

- Demo SwiftUI recorder exists.
- Real Core Location recorder, persistence, GPX generation, and save flow still required.

### 4.4 GPX Import

Functional requirements:

- User can import GPX from Files, Share Sheet, or app picker.
- App parses GPX tracks, timestamps, elevation, and metadata.
- App validates bad/empty GPX files and explains failures.
- Imported rides can be titled, dated, and saved.
- App uploads original GPX to storage.

Acceptance criteria:

- Valid GPX produces route preview, distance, duration, elevation, speed profile, and save action.
- Invalid GPX never crashes the app.
- User can cancel import before saving.
- Imported GPX is available for export later.

### 4.5 Ride Replay

Functional requirements:

- Ride detail displays a full route map.
- User can replay ride over time.
- Replay supports scrubber, play/pause, speed controls, and live telemetry readout.
- Map highlights speed ranges.
- Elevation and speed profiles remain synced with scrub position.

Acceptance criteria:

- Scrubbing updates map position and telemetry immediately.
- Playback speed can be changed without desync.
- Route remains visible and framed on map.
- Replay works for imported and recorded rides.

Current native status:

- Ride detail map, replay timeline, scrubber, live replay telemetry, and evidence-linked map focus are implemented.
- Selecting a chart point or coaching event returns to a corner-scale map view of that moment.

### 4.6 Analytics and Charts

Functional requirements:

- Show elevation profile.
- Show speed profile.
- Show acceleration profile with braking and drive zones.
- Show corner speed vs radius with constant-grip reference curves.
- Show approximate grip-usage diagram.
- Show historical weather at ride time.

Acceptance criteria:

- Charts use the same parsed point stream.
- Charts remain understandable to non-technical riders.
- Any derived value is marked approximate where appropriate.
- Missing GPS/elevation/time data produces graceful degraded states.

Current native status:

- Combined elevation and speed profile with independent display modes is implemented.
- Acceleration profile, braking/drive bands, corner speed versus radius, and grip-usage diagram are implemented.
- Ride-specific plain-English insights and a progressively disclosed reading guide are implemented.
- Ride Coach includes a five-axis technique polygon, debrief, trend, and expandable score captions.
- Rider Craft includes its own calibration-aware reading guide and replay-linked evidence.

### 4.7 Ride Coach

Functional requirements:

- Analyze GPS point stream and produce technique scores:
  - Corner entry
  - Exit drive
  - Braking feel
  - Throttle feel
  - Consistency
  - Overall flow
- Generate plain-English debrief.
- Provide one clear thing to practice next ride.
- Compare trends against recent rides.
- Detect corners and produce corner tickets:
  - Geometry glyph
  - IN/APEX/OUT speeds
  - Verdict chips
  - Coaching tip
  - Repeat-corner recognition

Acceptance criteria:

- Scores are 0-100.
- Scores never reward top speed as the objective.
- Debrief is readable and avoids shaming or risky advice.
- Repeat-corner recognition identifies previously ridden corners within tolerance.
- If data quality is too poor, app says analysis is unavailable rather than fabricating.

Current native status:

- Data models and corner ticket UI exist.
- Coaching engine needs port from `riderskills.js` or rewrite in Swift.

### 4.8 Moments and Rider Journal

Functional requirements:

- User can pin up to five moments per ride.
- Each moment has location, timestamp, note, and optional photo.
- Journal supports flipbook and gallery/list views.
- User can browse moments across rides.
- User can open the source ride from a moment.

Acceptance criteria:

- Moment is tied to exact route position.
- Moment notes persist and sync.
- Journal handles no moments with a useful empty state.
- Moment photos are compressed and uploaded safely.

Current native status:

- Journal screen exists with sample content.
- Real moment creation, editing, photo support, and persistence still required.

### 4.9 Stats

Functional requirements:

- Lifetime totals:
  - Total rides
  - Total distance
  - Total moving time
  - Total elevation
- Monthly ride chart.
- Personal bests:
  - Longest ride
  - Biggest climb
  - Best flow
  - Most consistent ride
- Skill trends over time.
- Map of everywhere ridden.
- Backfill/recompute missing stats where possible.

Acceptance criteria:

- Stats update after saving or deleting a ride.
- Stats compute from real user data.
- Empty state appears for new user.
- Trend charts do not break when only one ride exists.

Current native status:

- Stats screen exists with sample content.
- Real aggregation service still required.

### 4.10 Route Planner

Functional requirements:

- User can create a planned route on a map.
- User can drop waypoints.
- Route snaps to real roads.
- User can drag pins to adjust.
- User can click/tap route line to insert a stop.
- App shows live distance and elevation-gain preview.
- User can undo/redo edits.
- User can search places.
- User can save planned routes.
- User can export planned routes as GPX.

Native map options:

- Apple MapKit for first native implementation.
- External routing service for road snapping.
- Elevation service for route preview.

Acceptance criteria:

- Saved route reloads with waypoints and snapped path.
- Exported GPX works in common GPS apps.
- Undo/redo accurately restores previous route states.
- Route planning failure gives a useful message and lets user retry.

Current native status:

- Routes screen exists as premium mock/planned route browser.
- Full route builder still required.

### 4.11 Start Ride from Planned Route

Functional requirements:

- User can start recording from a saved planned route.
- App shows planned line and actual line.
- App shows current GPS position vs planned route.
- App shows off-route distance/status.
- Completed ride links back to planned route.
- Ride detail overlays planned vs actual track.
- App computes rough route match score.

Acceptance criteria:

- User can tell when they are on/off route.
- Saved ride stores `planned_route_id`.
- Planned vs actual overlay is visible in ride detail.
- Route match score handles detours gracefully.

### 4.12 Sharing

Functional requirements:

- User can export shareable ride card PNG.
- User can export replay video.
- User can create public read-only share link.
- User can revoke public share link.
- Shared page/card includes key stats and route artwork.

Acceptance criteria:

- Share card renders at consistent social size.
- Export includes real map/route artwork.
- Public link cannot mutate data.
- Revoking link immediately disables public access.

Current native status:

- ShareCard component exists.
- Share image generation partly exists.
- Public share links and video export still required.

### 4.13 Data Export and Ownership

Functional requirements:

- User can export all data as zip:
  - `rides.json`
  - all GPX files
  - moments metadata
  - planned routes
- User can delete account data.

Acceptance criteria:

- Export contains every ride visible in the app.
- Export process handles large accounts without freezing UI.
- Delete account requires confirmation and cannot happen accidentally.

### 4.14 Group / Social Ride Features

Functional requirements from existing repository scope:

- Group ride setup with description, schedule, meet point, visibility, and capacity.
- Native/web-compatible invite sharing and authenticated deep-link recovery.
- Community event discovery for rides explicitly published by their host.
- Riding, Maybe, and Not this time RSVP lifecycle, including leave.
- Organiser editing, response dashboard, cancellation, and completion.
- Group meet/live ride support where enabled.
- Profiles for social identity.

Acceptance criteria:

- Group features are optional and do not block solo use.
- Invite-only rides are excluded from community discovery.
- Capacity and event state are enforced server-side.
- Attendee identity is visible only to the host and participating members.
- Live sharing is explicit and user-controlled.
- No silent location sharing.

Build recommendation:

- Defer until core solo recording, routes, and sync are stable.

### 4.15 AI / Recommendations

Functional requirements from existing repository scope:

- Extract ride features.
- Generate ride feedback.
- Recommend next rides/routes/practice focus.
- Summarize skill trends.

Acceptance criteria:

- AI feedback is grounded in computed ride features.
- App distinguishes measured facts from generated advice.
- User can use the app without AI features.

Build recommendation:

- Keep AI as a later layer after analytics and coaching data are reliable.

### 4.16 Rider Craft

Rider Craft is a safety-first, post-ride skill-progression system built on the deterministic Ride Coach. Its governing rule is that no metric, target, badge, or interaction may be improved by riding faster, leaning further, or accepting more risk.

Functional requirements:

- Detect four GPS-supported survival-reaction proxies: braking after turn-in, flat exit, early apex, and braking deep into a corner.
- Preserve the corner and replay index for every detected event.
- Show survival reactions per corner as an error rate, not a score or grade.
- Select one persistent practice focus rather than asking the rider to improve every axis at once.
- Add safety-positive badges only after detector calibration.
- Show personal trends without public comparison, streaks, or frequency pressure.
- Teach road sense through unscored contextual cards where GPS cannot support a measurement.

Acceptance criteria:

- Detection is deterministic and covered by positive and negative fixtures.
- Poor GPS quality or insufficient corners produces an unavailable state.
- Thresholds are calibrated against a representative set of real rides before headline UI or badges ship.
- Every event links to evidence in ride replay.
- Advice is post-ride only and does not reward speed, lean angle, lateral load, ride frequency, or distance.
- A written perverse-incentive audit passes before each phase ships.

Explicit exclusions:

- No throttle-chop count from 1 Hz GPS.
- No speed, pace, lean-angle, or maximum-performance achievements.
- No leaderboards, streaks, live gamification, or fabricated composite progression score.
- No numeric Road Sense score.

Detailed delivery and calibration plan: `docs/rider-craft-feature-plan.md`.

### 4.17 Limit Point Analysis

Limit Point Analysis is a safety-critical route-study feature that estimates where road geometry may restrict forward visibility. Its primary surface is the pre-ride planned-route map, followed by replay-linked post-ride reflection. Live audio is a separately gated research candidate and is not part of the initial commitment.

Functional requirements:

- Compute versioned sight-distance, stopping-distance, and estimated-margin scenarios from route geometry and explicit assumptions.
- Preserve model version, geometry source, obstruction source, confidence, and limitations with every assessment.
- Analyse planned routes before riding without presenting a recommended speed.
- Show neutral study/restriction states rather than safe/clear states or performance colours.
- Link post-ride assessments to corner replay evidence.
- Return unavailable when geometry or obstruction evidence is insufficient.
- Keep all fixed-obstruction-clearance output developer-only until reality validation passes.

Acceptance criteria:

- Formula, boundary, and monotonicity tests prove that speed and reaction time cannot improve estimated margin.
- Radius noise, obstruction-clearance sensitivity, route simplification, false positives, and false negatives are documented against reviewed real roads.
- The rider-facing UI never describes positive margin as headroom, permission, safety, or a speed target.
- Missing alerts or unmarked bends never imply safety.
- Legal and safety review approves the claims before rider-facing release.
- Pre-ride and post-ride features remain fully useful with live audio disabled.

Explicit exclusions before independent approval:

- No lane-position score from consumer phone GPS.
- No green safe state, recommended corner speed, badge, streak, leaderboard, or sight-margin score.
- No fixed five-metre obstruction assumption in rider-facing UI.
- No free-ride live prediction.
- No visual live warning.
- No live audio warning until the dedicated release gates pass.

Current implementation note:

- The deterministic model, planned-route preview, recorded-speed review, map overlay, and replay links are implemented for Debug research builds.
- `LimitPointFeature.isResearchPreviewEnabled` hides every Limit Point rider surface in Release builds while the fixed-obstruction model remains unvalidated.
- Live audio and map-derived obstruction modelling are intentionally not implemented yet.

Detailed research, delivery, and safety plan: `docs/limit-point-analysis-feature-plan.md`.

## 5. Core Data Model

### 5.1 User Profile

- `id`
- `email`
- `display_name`
- `avatar_url`
- `created_at`
- `updated_at`

### 5.2 Ride

- `id`
- `user_id`
- `title`
- `source`: recorded, imported_gpx, strava, demo
- `ride_date`
- `created_at`
- `updated_at`
- `distance_m`
- `duration_s`
- `moving_duration_s`
- `elevation_gain_m`
- `gpx_path`
- `route_preview`
- `location_name`
- `weather`
- `moments`
- `skills`
- `flow_score`
- `planned_route_id`
- `is_public`
- `share_token`

### 5.3 Track Point

- `lat`
- `lon`
- `timestamp`
- `elevation_m`
- `speed_mps`
- `horizontal_accuracy_m`
- `vertical_accuracy_m`
- `course`

Storage recommendation:

- Original GPX in object storage.
- Derived summary in database.
- Optional compressed point stream for fast replay.

### 5.4 Moment

- `id`
- `ride_id`
- `timestamp`
- `coordinate`
- `note`
- `photo_path`
- `created_at`

### 5.5 Planned Route

- `id`
- `user_id`
- `title`
- `waypoints`
- `snapped_path`
- `distance_m`
- `elevation_gain_m`
- `estimated_duration_s`
- `created_at`
- `updated_at`

### 5.6 Corner Analysis

- `id`
- `ride_id`
- `start_distance_m`
- `apex_distance_m`
- `end_distance_m`
- `entry_speed_kmh`
- `apex_speed_kmh`
- `exit_speed_kmh`
- `radius_m`
- `verdict`
- `tip`
- `repeat_corner_key`

## 6. Native Service Architecture

### 6.1 Services

- `AuthService`
- `RideService`
- `RecordingService`
- `GPXService`
- `RideAnalysisService`
- `WeatherService`
- `RoutePlannerService`
- `ShareService`
- `ExportService`
- `ProfileService`

### 6.2 Service Rules

- All services should be protocol-first.
- SwiftUI screens receive services through dependency injection.
- Network calls use async/await.
- Long analysis tasks run off the main actor.
- UI models are separate from database transport models.
- Every screen must support loading, empty, error, and success states.

## 7. Permissions and Privacy

Required iOS permissions:

- When In Use Location
- Always Location for locked-screen ride recording
- Motion/Fitness optional if later used
- Photo Library add/read if moment photos are enabled
- Notifications optional for ride reminders or background recovery alerts

Rules:

- Location recording is user-initiated only.
- No silent background tracking.
- Explain Always permission before requesting it.
- Show visible recording state while recording.
- Let user stop recording at any time.

## 8. Offline and Recovery

Functional requirements:

- App shell works offline.
- Active ride recording persists locally first.
- Failed uploads queue for retry.
- User can recover unsaved ride after crash/kill.
- Saved local draft can be discarded.

Acceptance criteria:

- Network loss during recording does not lose ride.
- User can save ride after connectivity returns.
- App never duplicates the same recovered ride without confirmation.

## 9. Quality Bar

### 9.1 UX

- Premium, calm, dark-first interface.
- Fast launch.
- No blank screens.
- Meaningful empty/error states.
- One primary action per screen.
- Haptics for meaningful actions only.

### 9.2 Accessibility

- Dynamic Type support.
- VoiceOver labels for charts, maps, buttons, and share actions.
- 44pt minimum touch targets.
- Color contrast AA or better.
- Reduced Motion compatible.

### 9.3 Performance

- Long GPX files should not freeze the UI.
- Map rendering must remain smooth.
- Replay should handle large rides using downsampled display data.
- Analysis should be cancellable or backgrounded.

### 9.4 Safety

- Coaching copy must avoid risky speed-focused framing.
- Public sharing must be opt-in.
- Location sharing must be explicit.
- Data deletion requires confirmation.

## 10. Build Phases

### Phase 1: Native Foundation

Goal: SwiftUI app matches original app structure and can display real synced rides.

Deliverables:

- Auth/session.
- Supabase `RideService`.
- Real dashboard data.
- Ride detail from stored rides.
- GPX import and save.
- Basic stats from real rides.

### Phase 2: True Native Recording

Goal: reliable iPhone ride recording, including locked screen.

Deliverables:

- Core Location recording service.
- Background location capability.
- Local point persistence.
- Pause/resume.
- Finish/discard/save.
- Recovery after interruption.
- GPX generation from recorded track.

### Phase 3: Replay and Analysis

Goal: recorded/imported rides become rich ride memories.

Deliverables:

- Replay timeline and scrubber.
- Speed/elevation/acceleration charts.
- Ride Coach engine in Swift.
- Corner tickets.
- Historical weather.
- Moment pinning during and after rides.

### Phase 3B: Rider Craft Calibration and Progression

Goal: turn reliable Ride Coach evidence into safety-positive personal development without incentivising speed or risk.

Deliverables:

- Survival-reaction event models and four initial detectors.
- Replay-linked evidence and a restrained debrief line.
- Real-ride threshold calibration and detector fixtures.
- One-skill-at-a-time focus system after calibration passes.
- Safety-positive badges after focus-system validation.
- Personal Craft trends and unscored road-sense education.

Release gates:

- Phase 1 detector calibration must pass before the metric becomes headline UI.
- Each later phase requires a written perverse-incentive audit.
- Live recording remains free of gamification and coaching prompts.

### Phase 4: Route Planning

Goal: native route planning and follow-route ride mode.

Deliverables:

- Route builder.
- Road snapping.
- Place search.
- Save/export planned routes.
- Start ride from planned route.
- Planned vs actual overlay.
- Route match score.

### Phase 4B: Limit Point Route Study

Goal: add trustworthy pre-ride geometry study and replay-linked post-ride reflection without implying that the app can certify a bend as safe.

Deliverables:

- Pure Swift research model and calibration harness.
- Reality validation against reviewed roads and high-resolution geometry.
- Confidence-aware pre-ride study overlay after validation passes.
- Replay-linked post-ride evidence after pre-ride validation.
- Map/terrain-derived obstruction estimates as a later versioned model.

Release gates:

- Fixed-obstruction results remain developer-only.
- Representative false-positive and false-negative review passes.
- Safety, human-factors, and legal review approve rider-facing claims.
- Live audio remains a separate, final research candidate and does not block this phase.

### Phase 5: Sharing, Export, and Polish

Goal: complete original product promise.

Deliverables:

- Share card export.
- Replay video export.
- Public read-only share links.
- Full data export zip.
- Account settings.
- Delete data/account.
- App Store readiness pass.

### Phase 6: Social and AI Layer

Goal: add advanced features after the core solo rider loop is stable.

Deliverables:

- Group ride features.
- Live location sharing, explicit only.
- Profiles.
- AI ride feedback and recommendations.
- Trend-aware coaching refinements.

Current group-ride status:

- Native route-based creation, event details, visibility/capacity, hosted/joined lists, community discovery, lobby, three-state RSVP, attendee privacy, leaving, organiser editing/dashboard, cancellation/completion, sharing, and shared-route recording are implemented.
- Universal and custom app links preserve invites across authentication and open the native lobby. Universal links require deployment of the repository AASA file and a paid Apple team Release profile; Personal Team debug builds use the web lobby's custom app-link action.
- Group invite links remain compatible with the original web lobby.
- Notification preferences, local pre-ride reminders, APNs device registration,
  deep-link routing, a secure event outbox, RSVP/update triggers, quiet hours and
  the credential-gated delivery worker are implemented. Production remote delivery
  requires the paid Apple App ID push key and worker scheduler activation.
- Host handover, community moderation/messaging, and live rider positions remain pending.
- RSVP never implies live-location consent; live sharing requires a separate explicit control and field-validation gate.

## 11. Definition of Done

A feature is done when:

- It is implemented natively in SwiftUI.
- It uses the shared design system.
- It has loading, empty, error, and success states where applicable.
- It works with real persisted user data, not only sample data.
- It is covered by previews or tests where practical.
- It passes native iOS build.
- It does not regress existing web/Capacitor files.
- It is pushed to the active branch.
- Any coaching or progression metric documents its evidence, data-quality limits, and safety incentive audit.

## 12. Immediate Next Build Recommendation

The highest-value next step is Phase 1 plus Phase 2 bridge work:

1. Add native auth/session.
2. Implement Supabase-backed `RideService`.
3. Build GPX import/save.
4. Replace demo recorder telemetry with Core Location recording.
5. Persist active ride locally and save completed ride to Supabase.

Once those land, Memory Lanes stops being a beautiful prototype and becomes a real usable ride journal on iPhone.
