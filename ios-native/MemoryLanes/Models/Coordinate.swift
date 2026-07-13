import Foundation
import CoreLocation

// MARK: - Coordinate
//
// The domain model's own lat/lon type. We deliberately don't store
// `CLLocationCoordinate2D` in `Ride`: it isn't reliably `Sendable` and it drags
// CoreLocation into the model layer. `Coordinate` is a plain `Sendable` value,
// and we convert to `CLLocationCoordinate2D` only at the MapKit boundary.

struct Coordinate: Hashable, Sendable {
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
}

extension Array where Element == Coordinate {
    var clCoordinates: [CLLocationCoordinate2D] { map(\.clCoordinate) }
}
