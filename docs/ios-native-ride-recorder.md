# Native iOS Ride Recorder

This scaffold adds the next layer after the Capacitor shell: a native CoreLocation recorder that can keep receiving location updates while the iPhone is locked, as long as the user grants Always location permission and iOS allows the session to continue.

## What this adds

- `native/ios/MemoryLanesRideRecorderPlugin.swift`
  - Capacitor plugin scaffold using CoreLocation
  - Requests Always location permission
  - Starts/stops native location updates
  - Keeps an in-memory track while recording
  - Emits `rideRecorderPoint`, `rideRecorderStatus`, and `rideRecorderError` events to JavaScript
- `iosRideRecorder.js`
  - Browser-facing wrapper around `registerPlugin('MemoryLanesRideRecorder')`
  - Converts a native point list into GPX text with `nativeTrackToGPX()`

## Important iOS behavior

This is the correct native direction for background ride recording, but iOS still controls background execution. Recording is most reliable when:

- The user explicitly starts a ride.
- The app has Always location permission.
- Xcode has Background Modes > Location updates enabled.
- The app shows a clear recording indicator and stops recording when the user taps stop.

Do not use this to record silently or unexpectedly. App Review will expect the background location behavior to be obvious, user-initiated, and central to the app.

## Wire into the generated iOS app

First merge the Capacitor scaffold PR, then run:

```sh
npm install
npm run cap:add:ios
```

Then in Xcode:

1. Open `ios/App/App.xcworkspace`.
2. Drag `native/ios/MemoryLanesRideRecorderPlugin.swift` into `ios/App/App/`.
3. Make sure the file is added to the App target.
4. Select the App target > Signing & Capabilities.
5. Add Background Modes.
6. Enable Location updates.
7. Add the location usage keys below to `ios/App/App/Info.plist`.

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Memory Lanes uses your location to record and replay rides.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Memory Lanes records rides while your phone is locked after you start recording.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>Memory Lanes records rides while your phone is locked after you start recording.</string>
```

## Web integration example

Import the wrapper from a page or module that owns live ride recording:

```js
import {
  requestRideRecorderPermission,
  startNativeRideRecording,
  stopNativeRideRecording,
  getNativeRideTrack,
  nativeTrackToGPX,
  onNativeRidePoint,
  onNativeRideStatus
} from './iosRideRecorder.js';

async function startRecording() {
  const permission = await requestRideRecorderPermission();
  if (permission.location !== 'granted') {
    throw new Error('Always location permission is required for locked-screen recording.');
  }

  await onNativeRidePoint(point => {
    console.log('native ride point', point);
  });

  await onNativeRideStatus(status => {
    console.log('native ride status', status);
  });

  return startNativeRideRecording();
}

async function stopRecordingAndBuildGPX(title) {
  await stopNativeRideRecording();
  const track = await getNativeRideTrack();
  return nativeTrackToGPX(track, title);
}
```

## Integration status

`ride-live.js` is now wired to this plugin. It detects the native app with
`window.Capacitor?.isNativePlatform()` and, when true, records through the
CoreLocation plugin instead of the browser's `navigator.geolocation`
(lazy-importing `iosRideRecorder.js` only on native, so the web build never
touches the Capacitor CDN dependency). Because JavaScript is suspended while
the app is backgrounded, the live tracker does not rely on the per-point
event stream for data: it drains the plugin's authoritative buffer via
`getTrack()` on a 2-second timer, on every foreground resume, and once more on
Finish, replaying each new point through the same pipeline the web path uses.
Pause/Resume and "Add Moment" all work unchanged, and the saved GPX is built
from the merged track exactly as before.

## Next implementation step

The current Swift scaffold stores the active ride in memory. Before TestFlight,
persist points to disk during recording so a crash, battery kill, or OS
termination does not lose the ride. A simple next step is to append JSON lines
to a file in the app documents directory and rebuild GPX from that file on
stop/recovery. (The JS side already tolerates this: it re-reads the whole track
via `getTrack()`, so on-disk recovery would flow through without JS changes.)
