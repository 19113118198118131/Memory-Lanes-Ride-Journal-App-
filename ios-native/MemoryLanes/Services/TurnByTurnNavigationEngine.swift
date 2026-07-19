import Foundation

struct TurnByTurnNavigationEngine: Sendable {
    struct Configuration: Equatable, Sendable {
        var onRouteDistanceMeters = 80.0
        var nearRouteDistanceMeters = 175.0
        var arrivalDistanceMeters = 55.0
        var localSearchRadius = 180
        var maximumBackwardProgressMeters = 120.0
    }

    private let route: TurnByTurnRoute
    private let cumulativeDistances: [Double]
    private let geometryDistanceMeters: Double
    private let configuration: Configuration
    private var lastSegmentIndex: Int?
    private var lastProgressMeters = 0.0

    init(route: TurnByTurnRoute, configuration: Configuration = Configuration()) throws {
        guard route.coordinates.count > 1 else { throw TurnByTurnNavigationError.invalidRoute }
        self.route = route
        self.configuration = configuration
        cumulativeDistances = Self.cumulativeDistances(for: route.coordinates)
        geometryDistanceMeters = cumulativeDistances.last ?? 0
    }

    mutating func update(coordinate: Coordinate) -> TurnByTurnSnapshot {
        guard let match = nearestMatch(to: coordinate) else {
            return TurnByTurnSnapshot(
                state: .locating,
                instruction: route.instructions.first,
                upcomingInstruction: route.instructions.dropFirst().first,
                distanceToManeuverMeters: nil,
                remainingDistanceMeters: route.distanceMeters,
                remainingTravelTime: route.expectedTravelTime,
                progressPercent: 0,
                deviationMeters: nil,
                matchedDistanceMeters: 0
            )
        }

        lastSegmentIndex = match.segmentIndex
        let matchedProgress = max(
            match.distanceAlongRoute,
            lastProgressMeters - configuration.maximumBackwardProgressMeters
        )
        lastProgressMeters = max(lastProgressMeters, matchedProgress)
        let progress = lastProgressMeters
        let normalizedProgress = geometryDistanceMeters > 0 ? min(max(progress / geometryDistanceMeters, 0), 1) : 0
        let routeProgressMeters = normalizedProgress * max(route.distanceMeters, geometryDistanceMeters)
        let remainingDistance = max(route.distanceMeters - routeProgressMeters, 0)
        let remainingTime = route.distanceMeters > 0
            ? route.expectedTravelTime * remainingDistance / route.distanceMeters
            : 0
        let state = routeState(deviationMeters: match.deviationMeters, remainingDistanceMeters: remainingDistance)
        let instructionIndex = nextInstructionIndex(after: routeProgressMeters)
        let instruction = instructionIndex.map { route.instructions[$0] }
        let upcoming = instructionIndex.flatMap { index in
            route.instructions.indices.contains(index + 1) ? route.instructions[index + 1] : nil
        }
        let maneuverDistance = instruction.map { max($0.startsAtMeters - routeProgressMeters, 0) }

        return TurnByTurnSnapshot(
            state: state,
            instruction: state == .arrived ? nil : instruction,
            upcomingInstruction: upcoming,
            distanceToManeuverMeters: state == .arrived ? nil : maneuverDistance,
            remainingDistanceMeters: remainingDistance,
            remainingTravelTime: remainingTime,
            progressPercent: normalizedProgress * 100,
            deviationMeters: match.deviationMeters,
            matchedDistanceMeters: routeProgressMeters
        )
    }

    private func routeState(deviationMeters: Double, remainingDistanceMeters: Double) -> NavigationRouteState {
        if remainingDistanceMeters <= configuration.arrivalDistanceMeters,
           deviationMeters <= configuration.nearRouteDistanceMeters {
            return .arrived
        }
        if deviationMeters <= configuration.onRouteDistanceMeters { return .onRoute }
        if deviationMeters <= configuration.nearRouteDistanceMeters { return .nearRoute }
        return .offRoute
    }

    private func nextInstructionIndex(after progressMeters: Double) -> Int? {
        guard !route.instructions.isEmpty else { return nil }
        if progressMeters < 20 { return 0 }
        return route.instructions.firstIndex { $0.startsAtMeters > progressMeters + 12 }
            ?? route.instructions.indices.last
    }

    private mutating func nearestMatch(to coordinate: Coordinate) -> Match? {
        let indices: Range<Int>
        if let lastSegmentIndex {
            let lower = max(0, lastSegmentIndex - configuration.localSearchRadius / 4)
            let upper = min(route.coordinates.count - 1, lastSegmentIndex + configuration.localSearchRadius)
            indices = lower..<upper
        } else {
            indices = 0..<(route.coordinates.count - 1)
        }

        var best = bestMatch(to: coordinate, indices: indices)
        if best?.deviationMeters ?? .infinity > configuration.nearRouteDistanceMeters * 2,
           lastSegmentIndex != nil {
            best = bestMatch(to: coordinate, indices: 0..<(route.coordinates.count - 1))
        }
        return best
    }

    private func bestMatch(to coordinate: Coordinate, indices: Range<Int>) -> Match? {
        var best: Match?
        for index in indices {
            let projection = Self.projection(
                of: coordinate,
                onto: route.coordinates[index],
                and: route.coordinates[index + 1]
            )
            let segmentLength = cumulativeDistances[index + 1] - cumulativeDistances[index]
            let candidate = Match(
                segmentIndex: index,
                deviationMeters: projection.distanceMeters,
                distanceAlongRoute: cumulativeDistances[index] + segmentLength * projection.fraction
            )
            guard let existing = best else {
                best = candidate
                continue
            }

            let candidateRegression = max(lastProgressMeters - candidate.distanceAlongRoute, 0)
            let existingRegression = max(lastProgressMeters - existing.distanceAlongRoute, 0)
            let candidateScore = candidate.deviationMeters + candidateRegression * 0.35
            let existingScore = existing.deviationMeters + existingRegression * 0.35
            if candidateScore < existingScore { best = candidate }
        }
        return best
    }

    private static func cumulativeDistances(for coordinates: [Coordinate]) -> [Double] {
        guard !coordinates.isEmpty else { return [] }
        var result = [0.0]
        for index in coordinates.indices.dropFirst() {
            result.append(result[index - 1] + distanceMeters(coordinates[index - 1], coordinates[index]))
        }
        return result
    }

    private static func projection(of point: Coordinate, onto start: Coordinate, and end: Coordinate) -> Projection {
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
        return Projection(
            distanceMeters: hypot(startX + segmentX * fraction, startY + segmentY * fraction),
            fraction: fraction
        )
    }

    private static func distanceMeters(_ first: Coordinate, _ second: Coordinate) -> Double {
        let latitudeScale = 111_132.0
        let longitudeScale = 111_320.0 * cos(first.latitude * .pi / 180)
        return hypot(
            (second.longitude - first.longitude) * longitudeScale,
            (second.latitude - first.latitude) * latitudeScale
        )
    }
}

struct NavigationRecoveryPlanner {
    static func waypoints(
        from current: Coordinate,
        plannedRoute: PlannedRoute,
        progressPercent: Double
    ) -> [Coordinate] {
        let route = plannedRoute.route
        guard route.count > 1 else { return [current] + plannedRoute.waypoints }
        let progress = min(max(progressPercent / 100, 0), 1)
        let currentIndex = Int((Double(route.count - 1) * progress).rounded())
        let reconnectOffset = max(route.count / 30, 1)
        let reconnectIndex = min(currentIndex + reconnectOffset, route.count - 1)
        let reconnect = route[reconnectIndex]
        let remainingWaypoints = plannedRoute.waypoints.filter { waypoint in
            guard let index = nearestIndex(to: waypoint, in: route) else { return false }
            return index > reconnectIndex
        }
        let destination = route.last.map { [$0] } ?? []
        return deduplicated([current, reconnect] + remainingWaypoints + destination)
    }

    private static func nearestIndex(to coordinate: Coordinate, in route: [Coordinate]) -> Int? {
        route.indices.min { lhs, rhs in
            squaredDistance(route[lhs], coordinate) < squaredDistance(route[rhs], coordinate)
        }
    }

    private static func squaredDistance(_ first: Coordinate, _ second: Coordinate) -> Double {
        let latitude = first.latitude - second.latitude
        let longitude = first.longitude - second.longitude
        return latitude * latitude + longitude * longitude
    }

    private static func deduplicated(_ coordinates: [Coordinate]) -> [Coordinate] {
        coordinates.reduce(into: []) { result, coordinate in
            guard result.last.map({ squaredDistance($0, coordinate) > 0.00000001 }) ?? true else { return }
            result.append(coordinate)
        }
    }
}

private struct Match {
    let segmentIndex: Int
    let deviationMeters: Double
    let distanceAlongRoute: Double
}

private struct Projection {
    let distanceMeters: Double
    let fraction: Double
}
