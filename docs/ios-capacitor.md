# iOS Capacitor Scaffold

This repo is still a static web app at its core. Capacitor wraps that app in a native iOS shell and gives us a path to native APIs such as location, notifications, and background tasks.

## First setup

```sh
npm install
npm run build:web
npm run cap:add:ios
npm run ios:open
```

After the iOS project exists, use this loop for web changes:

```sh
npm run cap:sync
npm run ios:open
```

## Background behavior on iOS

iOS does not allow arbitrary always-running background JavaScript. Capacitor Background Runner is for short, OS-scheduled bursts of work. On iOS, background runs are not guaranteed to happen at the requested interval, and each run has a short execution window.

Use Background Runner for small jobs such as queue cleanup, sync, reminders, or checking for unsent ride summaries.

For true ride recording while the screen is locked, use the native CoreLocation bridge scaffold in `docs/ios-native-ride-recorder.md`. It records from native Swift instead of relying on background JavaScript.

## Xcode setup for Background Runner

In Xcode, open `ios/App/App.xcworkspace`, select the app target, and enable:

- Background Modes
- Background fetch
- Background processing
- Location updates, only if implementing background ride recording

Add this to `Info.plist`:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>app.memorylanes.background.task</string>
</array>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Memory Lanes uses your location to record and replay rides.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Memory Lanes can record rides while your phone is locked when you start a ride.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>Memory Lanes can record rides while your phone is locked when you start a ride.</string>
```

In `ios/App/App/AppDelegate.swift`, import and register Background Runner:

```swift
import Capacitor
import CapacitorBackgroundRunner

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    BackgroundRunnerPlugin.registerBackgroundTask()
    BackgroundRunnerPlugin.handleApplicationDidFinishLaunching(launchOptions: launchOptions)
    return true
}
```

## What is scaffolded

- `package.json`: Capacitor dependencies and scripts
- `capacitor.config.ts`: iOS app id/name and Background Runner config
- `scripts/prepare-capacitor-web.mjs`: copies static runtime assets into `www/`
- `runners/background.js`: starter background task handler
- `.gitignore`: ignores generated local/native build outputs
- `native/ios/MemoryLanesRideRecorderPlugin.swift`: native location recorder bridge scaffold
- `iosRideRecorder.js`: web wrapper for the native recorder

## Next native step

After the recorder bridge is added to Xcode, persist points to disk during recording so a crash, battery kill, or OS termination cannot lose a ride. A simple first version can append JSON lines to a file and rebuild GPX from that file on stop or recovery.
