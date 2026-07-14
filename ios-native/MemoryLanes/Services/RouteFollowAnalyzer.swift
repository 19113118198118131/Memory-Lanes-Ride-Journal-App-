import Foundation

struct RouteFollowSnapshot: Sendable {
    let plannedDistanceKm: Double
    let routeProgressPercent: Double
    let remainingDistanceKm: Double
    let currentDeviationMeters: Double?
    let onRoutePercent: Double
    let guidanceTitle: String
    let guidanceDetail: String
    let guidanceSymbol: String

    var progressPercent: Double {
        min(max(routeProgressPercent, 0), 100)
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
        let coordinates = route.route
        let cumulative = cumulativeDistances(for: coordinates)
        let geometryDistance = cumulative.last ?? 0
        let plannedDistanceKm = route.distanceKm ?? geometryDistance / 1000
        let preferredDistance = min(max(distanceMeters, 0), geometryDistance)
        let currentMatch = recordedPoints.last.flatMap {
            nearestMatch(
                from: $0.coordinate,
                to: coordinates,
                cumulative: cumulative,
                preferredDistance: preferredDistance
            )
        }
        let routeProgress = geometryDistance > 0
            ? (currentMatch?.distanceAlongRoute ?? 0) / geometryDistance
            : 0
        let remainingDistanceKm = max(plannedDistanceKm * (1 - routeProgress), 0)

        let sampledPoints = sampled(recordedPoints, maximumCount: 120)
        let sampledDeviations = sampledPoints.compactMap {
            nearestMatch(from: $0.coordinate, to: coordinates, cumulative: cumulative)?.deviationMeters
        }
        let onRoutePercent = sampledDeviations.isEmpty
            ? 0
            : Double(sampledDeviations.filter { $0 <= 150 }.count) / Double(sampledDeviations.count) * 100
        let guidance = guidance(
            current: recordedPoints.last?.coordinate,
            route: coordinates,
            cumulative: cumulative,
            match: currentMatch,
            remainingDistanceKm: remainingDistanceKm
        )

        return RouteFollowSnapshot(
            plannedDistanceKm: plannedDistanceKm,
            routeProgressPercent: routeProgress * 100,
            remainingDistanceKm: remainingDistanceKm,
            currentDeviationMeters: currentMatch?.deviationMeters,
            onRoutePercent: onRoutePercent,
            guidanceTitle: guidance.title,
            guidanceDetail: guidance.detail,
            guidanceSymbol: guidance.symbol
        )
    }

    private func guidance(
        current: Coordinate?,
        route: [Coordinate],
        cumulative: [Double],
        match: RouteMatch?,
        remainingDistanceKm: Double
    ) -> Guidance {
        guard let current, let match, route.count > 1 else {
            return Guidance(title: "Finding route", detail: "Waiting for a reliable GPS fix", symbol: "location.magnifyingglass")
        }

        if match.deviationMeters > 175 {
            let target = route[min(match.segmentIndex + 1, route.count - 1)]
            let direction = cardinalDirection(for: bearing(from: current, to: target))
            return Guidance(
                title: "Return to route",
                detail: String(format: "Route is %.0f m %@", match.deviationMeters, direction),
                symbol: "location.fill.viewfinder"
            )
        }

        if remainingDistanceKm <= 0.1 {
            return Guidance(title: "Finish ahead", detail: "Complete the planned route", symbol: "flag.checkered")
        }

        guard let turn = nextTurn(route: route, cumulative: cumulative, after: match.distanceAlongRoute) else {
            return Guidance(
                title: "Continue on route",
                detail: String(format: "%.1f km remaining", remainingDistanceKm),
                symbol: "arrow.up"
            )
        }

        let isRight = turn.angle > 0
        return Guidance(
            title: isRight ? "Right ahead" : "Left ahead",
            detail: turn.distanceMeters >= 1_000
                ? String(format: "in %.1f km", turn.distanceMeters / 1_000)
                : String(format: "in %.0f m", turn.distanceMeters),
            symbol: isRight ? "arrow.turn.up.right" : "arrow.turn.up.left"
        )
    }

    private func nextTurn(route: [Coordinate], cumulative: [Double], after distance: Double) -> Turn? {
        guard route.count > 2, let total = cumulative.last, distance < total else { return nil }
        let baseIndex = index(atOrAfter: distance + 80, cumulative: cumulative)
        let baseEndIndex = index(atOrAfter: distance + 180, cumulative: cumulative)
        guard baseIndex < route.count, baseEndIndex < route.count, baseIndex != baseEndIndex else { return nil }
        let baseBearing = bearing(from: route[baseIndex], to: route[baseEndIndex])

        var scanDistance = distance + 140
        let scanLimit = min(distance + 1_200, total)
        while scanDistance < scanLimit {
            let candidateIndex = index(atOrAfter: scanDistance, cumulative: cumulative)
            let candidateEndIndex = index(atOrAfter: scanDistance + 110, cumulative: cumulative)
            guard candidateIndex < route.count, candidateEndIndex < route.count else { break }
            if candidateIndex != candidateEndIndex {
                let candidateBearing = bearing(from: route[candidateIndex], to: route[candidateEndIndex])
                let angle = normalizedAngle(candidateBearing - baseBearing)
                if abs(angle) >= 38 {
                    return Turn(angle: angle, distanceMeters: max(cumulative[candidateIndex] - distance, 0))
                }
            }
            scanDistance += 80
        }
        return nil
    }

    private func nearestMatch(
        from coordinate: Coordinate,
        to route: [Coordinate],
        cumulative: [Double],
        preferredDistance: Double? = nil
    ) -> RouteMatch? {
        guard route.count > 1, cumulative.count == route.count else { return nil }
        var best: RouteMatch?

        for index in route.indices.dropLast() {
            let projection = projection(of: coordinate, onto: route[index], and: route[index + 1])
            let segmentLength = cumulative[index + 1] - cumulative[index]
            let candidate = RouteMatch(
                segmentIndex: index,
                deviationMeters: projection.distanceMeters,
                distanceAlongRoute: cumulative[index] + segmentLength * projection.fraction
            )
            guard let existing = best else {
                best = candidate
                continue
            }

            if candidate.deviationMeters < existing.deviationMeters - 1 {
                best = candidate
            } else if abs(candidate.deviationMeters - existing.deviationMeters) <= 20,
                      let preferredDistance,
                      abs(candidate.distanceAlongRoute - preferredDistance) < abs(existing.distanceAlongRoute - preferredDistance) {
                best = candidate
            }
        }
        return best
    }

    private func projection(of point: Coordinate, onto start: Coordinate, and end: Coordinate) -> Projection {
        let latitudeScale = 111_132.0
        let longitudeScale = 111_320.0 * cos(point.latitude * .pi / 180)
        let startX = (start.longitude - point.longitude) * longitudeScale
        let startY = (start.latitude - point.latitude) * latitudeScale
        let endX = (end.longitude - point.longitude) * longitudeScale
        let endY = (end.latitude - point.latitude) * latitudeScale
        let segmentX = endX - startX
        let segmentY = endY - startY
        let lengthSquared = segmentX * segmentX + segmentY * segmentY
        let fraction = lengthSquared > 0
            ? min(max(-(startX * segmentX + startY * segmentY) / lengthSquared, 0), 1)
            : 0
        let closestX = startX + segmentX * fraction
        let closestY = startY + segmentY * fraction
        return Projection(distanceMeters: hypot(closestX, closestY), fraction: fraction)
    }

    private func cumulativeDistances(for route: [Coordinate]) -> [Double] {
        guard !route.isEmpty else { return [] }
        var distances = [0.0]
        for index in route.indices.dropFirst() {
            distances.append(distances[index - 1] + route[index - 1].distanceMeters(to: route[index]))
        }
        return distances
    }

    private func sampled(_ points: [RecordingPoint], maximumCount: Int) -> [RecordingPoint] {
        guard points.count > maximumCount else { return points }
        let interval = Double(points.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { points[Int((Double($0) * interval).rounded())] }
    }

    private func index(atOrAfter distance: Double, cumulative: [Double]) -> Int {
        var lower = 0
        var upper = cumulative.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cumulative[middle] < distance {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return min(lower, max(cumulative.count - 1, 0))
    }

    private func bearing(from start: Coordinate, to end: Coordinate) -> Double {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        (angle + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    private func cardinalDirection(for bearing: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return directions[Int((bearing / 45).rounded()) % directions.count]
    }
}

private struct RouteMatch {
    let segmentIndex: Int
    let deviationMeters: Double
    let distanceAlongRoute: Double
}

private struct Projection {
    let distanceMeters: Double
    let fraction: Double
}

private struct Guidance {
    let title: String
    let detail: String
    let symbol: String
}

private struct Turn {
    let angle: Double
    let distanceMeters: Double
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
