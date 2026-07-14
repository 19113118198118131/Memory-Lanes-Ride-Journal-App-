# Memory Lanes 🏍️

**Journal your ride.** Upload a GPX track from any motorcycle GPS or phone app and Memory Lanes turns it into a map replay, a technique debrief, and a journal entry worth keeping.

Live app: deployed on Vercel. Replace this line with your production URL (for example `https://memory-lanes-ride-journal-app.vercel.app`).

New here? Click **"Try a sample ride"** on the landing page to explore every feature with a bundled demo GPX before uploading your own.

## Features

**Replay and analytics**
- Upload GPX, replay the ride on a Leaflet map with scrubbing, playback speeds, and live telemetry
- Elevation and speed profile, corner speed vs radius with constant-grip reference curves, acceleration profile with braking and drive zones shaded, and a g-g grip-usage diagram
- Historical weather at ride time (temperature, conditions, wind) via Open-Meteo
- Speed-range highlighting on the map

**Ride Coach**
- GPS-based technique feedback computed on a high-resolution point stream: corner entry, exit drive, braking feel, throttle feel, and consistency, each scored 0 to 100
- A plain-English debrief with one thing to practise next ride, plus a trend line comparing against your recent rides
- Corner tickets: geometry glyph, IN › APEX › OUT speeds, verdict chips, a coaching tip, and repeat-corner recognition ("You have ridden this corner 4 times, apex today 52 km/h, a new best!")
- Design principle: scores reward smoothness, technique and consistency, never speed or lean angle

**Journal and sharing**
- Pin up to five moments per ride with notes; browse them in the Rider's Journal (flipbook and gallery views)
- Lifetime stats page: totals, rides per month, personal bests, skill trends over time, and a map of everywhere you have ridden
- Shareable ride card PNG and replay video exports, drawn over real map tiles
- Public read-only share links per ride (token-based, revocable)
- One-click export of all your data (rides.json plus every GPX) as a zip

**Route Planner**
- Plan a route from scratch on the map: click to drop waypoints, the route snaps to real roads automatically (OSRM), drag pins to adjust, click the line to insert a stop
- Live distance and elevation-gain preview, undo/redo, place search (Photon)
- Save planned routes to your account, or export any of them as a GPX file for your GPS/phone
- **Start Ride**: follow a saved route live on the map (GPS position vs. the plan, on/off-route distance), record the actual track, and save it as a normal ride log linked back to the plan — the saved ride then overlays the planned line against your actual line with a rough "route match" score

**App**
- Installable PWA with offline app-shell caching
- Experimental route editor (drag, bulk add/delete points, multi-segment GPX export)

## Setup

This is a static app (no build step) backed by Supabase.

1. **Supabase project**: create one, then create a `ride_logs` table (columns used: `id`, `user_id`, `title`, `distance_km`, `duration_min`, `elevation_m`, `ride_date`, `gpx_path`, `moments jsonb`) and a public storage bucket named `gpx-files`. Enable Row Level Security so users can only read/write their own rows and their own storage folder.
2. **Migrations** (Supabase Dashboard → SQL Editor):
   - `supabase-share-setup.sql` - enables public share links (adds `is_public`, `share_token`, and a `get_shared_ride(token)` function)
   - `supabase-skills-setup.sql` - enables skill trends and repeat-corner recognition (adds a `skills jsonb` column)
   - `supabase-routeplanner-setup.sql` - enables the Route Planner (creates a `planned_routes` table, owner-only RLS)
   - `supabase-liveride-setup.sql` - enables Start Ride (adds `ride_logs.planned_route_id`, linking a recorded ride back to the plan it followed)
3. **Keys**: put your project URL and anon key in `supabaseClient.js`. The anon key is public by design, but only safe with RLS enabled.
4. **Deploy**: serve the repository root from any static host. GitHub Pages (main branch, root) is what the live app uses.

## Architecture

| File | Role |
|---|---|
| `index.html` + `script.js` | Landing, upload, replay, charts, moments, edit mode, sharing, exports |
| `riderskills.js` | Ride Coach engine: corner/braking detection, scores, debrief, storage summaries |
| `dashboard.html/js` | Ride list, filters, delete, data export |
| `stats.html/js` | Lifetime totals, monthly chart, personal bests, skill trends, all-routes map, backfill |
| `journal.html/js` | Rider's Journal (moments flipbook/gallery) |
| `planner.html/js` | Route Planner: click-to-plan routes snapped to roads, save/export GPX |
| `ride-live.html/js` | Start Ride: live GPS follow of a planned route, records and saves the actual ride |
| `supabaseClient.js` | Supabase client singleton |
| `sw.js`, `manifest.webmanifest` | PWA |

Cache-busting: all HTML pages reference CSS/JS with `?v=N` query strings. Bump `N` (and the `CACHE` name in `sw.js`) when deploying changes.

## Data and attribution

- Map tiles: © OpenStreetMap contributors; dark basemap for exports © CARTO
- Weather: Open-Meteo (no API key, non-commercial use)
- All skill analysis is derived from GPS positions and is approximate. It is feedback for reflection, not telemetry. Ride within your limits and the law.

## Roadmap ideas

Password reset flow, reverse-geocoded ride locations, weather caching, trend-aware coaching refinements, and a proper tile-source upgrade (MapTiler/Stadia) if traffic grows.

The native roadmap now also includes safety-gated Limit Point Analysis: pre-ride study of geometry that may restrict sight distance, followed by replay-linked post-ride reflection. Fixed-clearance estimates remain research-only, and live audio is explicitly deferred until reality validation, human-factors testing, and legal review pass. See `docs/limit-point-analysis-feature-plan.md`.

The native Analytics and Rider Craft reading model is documented in `docs/native-analytics-reading-guide.md`.
