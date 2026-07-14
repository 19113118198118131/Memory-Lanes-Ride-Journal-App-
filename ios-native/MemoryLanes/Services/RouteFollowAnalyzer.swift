import Foundation

struct RouteFollowSnapshot: Sendable {
    let plannedDistanceKm: Double
    let recordedDistanceKm: Double
    let remainingDistanceKm: Double
    let currentDeviationMeters: Double?
    let onRoutePercent: Double

    var progressPercent: Double {
        guard plannedDistanceKm > 0 else { return 0 }
        return min(max(recordedDistanceKm / plannedDistanceKm * 100, 0), 100)
    }

    var remainingText: String {
        String(format: "%.1f km", remainingDistanceKm)
    }

    var deviationText: String {
        guard let currentDeviationMeters else { return "--" }
        return String(format: "%.0f m", currentDeviationMeters)
    }

    var onRouteText: String {
        String(format: "%.0f%%", onRoutePercent)
    }

    var status: String {
        guard let currentDeviationMeters else { return "Waiting for GPS" }
        if currentDeviationMeters <= 75 { return "On route" }
        if currentDeviationMeters <= 175 { return "Near route" }
        return "Off route"
    }
}

struct RouteFollowAnalyzer {
    func snapshot(route: PlannedRoute, recordedPoints: [RecordingPoint], distanceMeters: Double) -> RouteFollowSnapshot {
        let plannedDistance = route.distanceKm ?? route.route.coordinateDistanceKm
        let recordedDistance = distanceMeters / 1000
        let remaining = max(plannedDistance - recordedDistance, 0)
        let deviations = recordedPoints.map { point in
            nearestDistance(from: point.coordinate, to: route.route)
        }
        let currentDeviation = deviations.last
        let onRoutePercent: Double
        if deviations.isEmpty {
            onRoutePercent = 0
        } else {
            let onRouteCount = deviations.filter { $0 <= 150 }.count
            onRoutePercent = Double(onRouteCount) / Double(deviations.count) * 100
        }

        return RouteFollowSnapshot(
            plannedDistanceKm: plannedDistance,
            recordedDistanceKm: recordedDistance,
            remainingDistanceKm: remaining,
            currentDeviationMeters: currentDeviation,
            onRoutePercent: onRoutePercent
        )
    }

    private func nearestDistance(from coordinate: Coordinate, to route: [Coordinate]) -> Double {
        guard !route.isEmpty else { return 0 }
        return route.map { coordinate.distanceMeters(to: $0) }.min() ?? 0
    }
}

private extension Array where Element == Coordinate {
    var coordinateDistanceKm: Double {
        guard count > 1 else { return 0 }
        return zip(self, dropFirst()).reduce(0) { total, pair in
            total + pair.0.distanceMeters(to: pair.1) / 1000
        }
    }
}

private extension Coordinate {
    func distanceMeters(to other: Coordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let startLat = latitude * .pi / 180
        let endLat = other.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            sin(dLon / 2) * sin(dLon / 2) * cos(startLat) * cos(endLat)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }
}
