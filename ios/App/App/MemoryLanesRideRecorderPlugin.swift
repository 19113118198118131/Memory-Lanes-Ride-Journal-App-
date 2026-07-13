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
    private var points: [[String: Any]] = []
    private var isRecording = false
    private var startedAt: Date?
    private var permissionCallID: String?

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

        let status = CLLocationManager.authorizationStatus()
        if status == .notDetermined {
            bridge?.saveCall(call)
            permissionCallID = call.callbackId
            manager.requestAlwaysAuthorization()
            return
        }

        if status == .authorizedWhenInUse {
            bridge?.saveCall(call)
            permissionCallID = call.callbackId
            manager.requestAlwaysAuthorization()
            return
        }

        checkPermissions(call)
    }

    @objc public func start(_ call: CAPPluginCall) {
        guard CLLocationManager.locationServicesEnabled() else {
            call.reject("Location services are disabled")
            return
        }

        guard CLLocationManager.authorizationStatus() == .authorizedAlways else {
            call.reject("Always location permission is required for background ride recording")
            return
        }

        points.removeAll()
        startedAt = Date()
        isRecording = true
        manager.startUpdatingLocation()

        notifyListeners("rideRecorderStatus", data: statusPayload())
        call.resolve(statusPayload())
    }

    @objc public func stop(_ call: CAPPluginCall) {
        manager.stopUpdatingLocation()
        isRecording = false

        let payload = statusPayload()
        notifyListeners("rideRecorderStatus", data: payload)
        call.resolve(payload)
    }

    @objc public func getStatus(_ call: CAPPluginCall) {
        call.resolve(statusPayload())
    }

    @objc public func getTrack(_ call: CAPPluginCall) {
        call.resolve([
            "startedAt": isoString(startedAt),
            "pointCount": points.count,
            "points": points
        ])
    }

    @objc public func clear(_ call: CAPPluginCall) {
        guard !isRecording else {
            call.reject("Stop recording before clearing the track")
            return
        }

        points.removeAll()
        startedAt = nil
        call.resolve(statusPayload())
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
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
            notifyListeners("rideRecorderPoint", data: point)
        }

        notifyListeners("rideRecorderStatus", data: statusPayload())
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        notifyListeners("rideRecorderError", data: ["message": error.localizedDescription])
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        finishPermissionCallIfNeeded()
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        finishPermissionCallIfNeeded()
    }

    private func finishPermissionCallIfNeeded() {
        guard let callID = permissionCallID, let call = bridge?.getSavedCall(callID) else { return }
        permissionCallID = nil
        checkPermissions(call)
        bridge?.releaseCall(call)
    }

    private func permissionState() -> String {
        switch CLLocationManager.authorizationStatus() {
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
        return [
            "recording": isRecording,
            "startedAt": isoString(startedAt) as Any,
            "pointCount": points.count,
            "permission": permissionState()
        ]
    }

    private func isoString(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
