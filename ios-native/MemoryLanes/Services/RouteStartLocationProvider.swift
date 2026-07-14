import Foundation
import CoreLocation

@MainActor
final class RouteStartLocationProvider: NSObject, ObservableObject {
    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var isLocating = false
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private var shouldRequestLocationAfterPermission = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var summary: String {
        if let coordinate {
            return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        }
        return "Use current location or the sample start"
    }

    func useCurrentLocation() {
        errorMessage = nil
        isLocating = true

        switch manager.authorizationStatus {
        case .notDetermined:
            shouldRequestLocationAfterPermission = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            isLocating = false
            errorMessage = "Allow location access in Settings to plan from your current position."
        @unknown default:
            isLocating = false
            errorMessage = "Current location is not available on this device."
        }
    }
}

extension RouteStartLocationProvider: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard shouldRequestLocationAfterPermission else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            shouldRequestLocationAfterPermission = false
            manager.requestLocation()
        case .denied, .restricted:
            shouldRequestLocationAfterPermission = false
            isLocating = false
            errorMessage = "Allow location access in Settings to plan from your current position."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        isLocating = false
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        errorMessage = "Could not find your current location."
    }
}
