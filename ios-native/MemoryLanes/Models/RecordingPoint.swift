import Foundation
import CoreLocation

// MARK: - RecordingPoint
//
// A single GPS fix captured during a live ride. This stays independent of
// CLLocation so it can be encoded to disk safely while the ride is in progress.

struct RecordingPoint: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let elevationMeters: Double
    let speedMetersPerSecond: Double
    let horizontalAccuracyMeters: Double
    let verticalAccuracyMeters: Double
    let courseDegrees: Double

    init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        elevationMeters = location.altitude
        speedMetersPerSecond = max(0, location.speed)
        horizontalAccuracyMeters = location.horizontalAccuracy
        verticalAccuracyMeters = location.verticalAccuracy
        courseDegrees = location.course
    }

    var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: elevationMeters,
            horizontalAccuracy: horizontalAccuracyMeters,
            verticalAccuracy: verticalAccuracyMeters,
            course: courseDegrees,
            speed: speedMetersPerSecond,
            timestamp: timestamp
        )
    }
}

extension Array where Element == RecordingPoint {
    var routePreview: [Coordinate] {
        guard count > 180 else { return map(\.coordinate) }
        let strideBy = Swift.max(1, count / 180)
        return enumerated().compactMap { index, point in
            index % strideBy == 0 ? point.coordinate : nil
        }
    }
}
