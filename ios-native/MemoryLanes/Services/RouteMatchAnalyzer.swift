import Foundation

struct RouteMatchAnalyzer {
    func analyze(plannedRoute: PlannedRoute, actualTrack: GPXTrack) -> RouteMatchSummary? {
        let planned = plannedRoute.route
        let actual = actualTrack.replayPoints.map(\.coordinate)
        guard planned.count > 1, actual.count > 1 else { return nil }

        let stride = max(actual.count / 180, 1)
        let sampledActual = actual.enumerated().compactMap { index, coordinate in
            index.isMultiple(of: stride) ? coordinate : nil
        }
        guard !sampledActual.isEmpty else { return nil }

        let deviations = sampledActual.map { actualPoint in
            planned.map { actualPoint.distanceMeters(to: $0) }.min() ?? 0
        }
        let matched = deviations.filter { $0 <= 150 }.count
        let matchedPercent = Double(matched) / Double(deviations.count) * 100
        let averageDeviation = deviations.reduce(0, +) / Double(deviations.count)
        let plannedDistanceKm = plannedRoute.distanceKm ?? planned.totalDistanceKm
        let actualDistanceKm = actualTrack.distanceMeters / 1000

        return RouteMatchSummary(
            plannedDistanceKm: plannedDistanceKm,
            actualDistanceKm: actualDistanceKm,
            distanceDeltaKm: actualDistanceKm - plannedDistanceKm,
            matchedPercent: matchedPercent,
            averageDeviationMeters: averageDeviation
        )
    }
}

private extension Array where Element == Coordinate {
    var totalDistanceKm: Double {
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
