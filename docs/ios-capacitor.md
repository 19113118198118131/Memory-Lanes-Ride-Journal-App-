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

For true ride recording while the screen is locked, build a native CoreLocation path that uses the iOS Location updates background mode and "Always" location permission. That can live beside this scaffold as a small Capacitor plugin or Swift bridge.

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

## Next native step

The next meaningful iOS feature is a dedicated "record ride in background" bridge:

1. Request `Always` location permission only when the user taps Start Ride.
2. Start a native CoreLocation session with background updates enabled.
3. Buffer points locally while offline or backgrounded.
4. Hand the completed GPX back to the existing save flow.
