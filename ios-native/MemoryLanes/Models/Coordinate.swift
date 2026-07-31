import Foundation
import CoreLocation

// MARK: - Coordinate
//
// The domain model's own lat/lon type. We deliberately don't store
// `CLLocationCoordinate2D` in `Ride`: it isn't reliably `Sendable` and it drags
// CoreLocation into the model layer. `Coordinate` is a plain `Sendable` value,
// and we convert to `CLLocationCoordinate2D` only at the MapKit boundary.

struct Coordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension Coordinate {
    /// Bridge to MapKit / CoreLocation at the view boundary.
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func projected(distanceKm: Double, bearingDegrees: Double) -> Coordinate {
        let earthRadiusKm = 6_371.0
        let angularDistance = distanceKm / earthRadiusKm
        let bearing = bearingDegrees * .pi / 180
        let startLatitude = latitude * .pi / 180
        let startLongitude = longitude * .pi / 180
        let endLatitude = asin(
            sin(startLatitude) * cos(angularDistance)
                + cos(startLatitude) * sin(angularDistance) * cos(bearing)
        )
        let endLongitude = startLongitude + atan2(
            sin(bearing) * sin(angularDistance) * cos(startLatitude),
            cos(angularDistance) - sin(startLatitude) * sin(endLatitude)
        )
        return Coordinate(
            latitude: endLatitude * 180 / .pi,
            longitude: endLongitude * 180 / .pi
        )
    }
}

extension Array where Element == Coordinate {
    var clCoordinates: [CLLocationCoordinate2D] { map(\.clCoordinate) }
}
