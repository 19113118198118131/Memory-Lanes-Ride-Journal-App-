import Foundation
import Capacitor
import CoreLocation

@objc(MemoryLanesRideRecorderPlugin)
public class MemoryLanesRideRecorderPlugin: CAPPlugin, CAPBridgedPlugin, CLLocationManagerDelegate {
    public let identifier = "MemoryLanesRideRecorderPlugin"
    public let jsName = "MemoryLanesRideRecorder"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getTrack", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise)
    ]

    private let manager = CLLocationManager()

    // Capacitor invokes plugin methods on a background queue while CoreLocation
    // delivers delegate callbacks on the main run loop. All three of these are
    // touched from both sides, so every read/write goes through this serial
    // queue to avoid a data race on the recorded track.
    private let stateQueue = DispatchQueue(label: "app.memorylanes.riderecorder.state")
    private var points: [[String: Any]] = []
    private var isRecording = false
    private var startedAt: Date?

    private var permissionCallID: String?

    // Reused across every recorded point instead of allocating per fix (a ride
    // can produce thousands of points).
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public override func load() {
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        call.resolve(["location": permissionState()])
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        guard CLLocationManager.locationServicesEnabled() else {
            call.reject("Location services are disabled")
            return
        }

        // Instance property (iOS 14+); the class method is deprecated and warns
        // about blocking the calling thread.
        let status = manager.authorizationStatus
        if status == .notDetermined || status == .authorizedWhenInUse {
            bridge?.saveCall(call)
            permissionCallID = call.callbackId
            // CLLocationManager must be driven from the main thread; Capacitor
            // invokes plugin methods on a background queue.
            DispatchQueue.main.async { self.manager.requestAlwaysAuthorization() }
            return
        }

        checkPermissions(call)
    }

    @objc public func start(_ call: CAPPluginCall) {
        guard CLLocationManager.locationServicesEnabled() else {
            call.reject("Location services are disabled")
            return
        }

        guard manager.authorizationStatus == .authorizedAlways else {
            call.reject("Always location permission is required for background ride recording")
            return
        }

        stateQueue.sync {
            points.removeAll()
            startedAt = Date()
            isRecording = true
        }
        DispatchQueue.main.async { self.manager.startUpdatingLocation() }

        let payload = statusPayload()
        notifyListeners("rideRecorderStatus", data: payload)
        call.resolve(payload)
    }

    @objc public func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async { self.manager.stopUpdatingLocation() }
        stateQueue.sync { isRecording = false }

        let payload = statusPayload()
        notifyListeners("rideRecorderStatus", data: payload)
        call.resolve(payload)
    }

    @objc public func getStatus(_ call: CAPPluginCall) {
        call.resolve(statusPayload())
    }

    @objc public func getTrack(_ call: CAPPluginCall) {
        var snapshot: [[String: Any]] = []
        var started: Date?
        stateQueue.sync {
            snapshot = points
            started = startedAt
        }
        call.resolve([
            "startedAt": isoString(started) as Any,
            "pointCount": snapshot.count,
            "points": snapshot
        ])
    }

    @objc public func clear(_ call: CAPPluginCall) {
        var recording = false
        stateQueue.sync { recording = isRecording }
        guard !recording else {
            call.reject("Stop recording before clearing the track")
            return
        }

        stateQueue.sync {
            points.removeAll()
            startedAt = nil
        }
        call.resolve(statusPayload())
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var newPoints: [[String: Any]] = []
        stateQueue.sync {
            guard isRecording else { return }
            for location in locations where location.horizontalAccuracy >= 0 {
                let point: [String: Any] = [
                    "lat": location.coordinate.latitude,
                    "lng": location.coordinate.longitude,
                    "accuracy": location.horizontalAccuracy,
                    "altitude": location.altitude,
                    "speed": max(location.speed, 0),
                    "course": location.course,
                    "timestamp": isoString(location.timestamp) ?? ""
                ]
                points.append(point)
                newPoints.append(point)
            }
        }

        guard !newPoints.isEmpty else { return }
        for point in newPoints {
            notifyListeners("rideRecorderPoint", data: point)
        }
        notifyListeners("rideRecorderStatus", data: statusPayload())
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        notifyListeners("rideRecorderError", data: ["message": error.localizedDescription])
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let callID = permissionCallID, let call = bridge?.getSavedCall(callID) else { return }
        permissionCallID = nil
        checkPermissions(call)
        bridge?.releaseCall(call)
    }

    private func permissionState() -> String {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            return "granted"
        case .authorizedWhenInUse:
            return "limited"
        case .denied, .restricted:
            return "denied"
        case .notDetermined:
            return "prompt"
        @unknown default:
            return "prompt"
        }
    }

    private func statusPayload() -> [String: Any] {
        var recording = false
        var count = 0
        var started: Date?
        stateQueue.sync {
            recording = isRecording
            count = points.count
            started = startedAt
        }
        return [
            "recording": recording,
            "startedAt": isoString(started) as Any,
            "pointCount": count,
            "permission": permissionState()
        ]
    }

    private func isoString(_ date: Date?) -> String? {
        guard let date else { return nil }
        return Self.isoFormatter.string(from: date)
    }
}
