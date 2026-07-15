import Foundation

struct IndependentRoutePlanner: Sendable {
    static let diversityOverlapLimit = 0.40

    private static let attemptCount = 14
    private static let concurrentAttemptLimit = 4
    private static let anchorRetryLimit = 3
    private static let explicitDistanceTolerance = 0.22
    private static let timeTolerance = 0.30

    private let roadProvider: any RoadRouteProviding
    private let characterAnalyzer: RouteCharacterAnalyzer
    private let randomSeed: UInt64?

    init(
        roadProvider: any RoadRouteProviding = MapKitRoadRouteProvider(),
        characterAnalyzer: RouteCharacterAnalyzer = RouteCharacterAnalyzer(),
        randomSeed: UInt64? = nil
    ) {
        self.roadProvider = roadProvider
        self.characterAnalyzer = characterAnalyzer
        self.randomSeed = randomSeed
    }

    func candidates(mood: RouteMood, time: RouteTime, start: Coordinate) async throws -> [RouteCandidate] {
        try await candidates(for: RoutePlanRequest(mood: mood, time: time, start: start))
    }

    func candidates(for request: RoutePlanRequest) async throws -> [RouteCandidate] {
        try Task.checkCancellation()
        let attempts = candidateAttempts(for: request, seed: runSeed())
        let evaluated = try await evaluate(attempts: attempts, request: request)
            .sorted { lhs, rhs in
                if lhs.selectionScore != rhs.selectionScore {
                    return lhs.selectionScore > rhs.selectionScore
                }
                return lhs.attemptIndex < rhs.attemptIndex
            }

        var selected: [EvaluatedCandidate] = []
        for evaluation in evaluated {
            try Task.checkCancellation()
            let isDiverse = selected.allSatisfy {
                RoutePolylineOverlap.sharedFraction(
                    evaluation.candidate.preview,
                    $0.candidate.preview
                ) <= Self.diversityOverlapLimit
            }
            if isDiverse {
                selected.append(evaluation)
            }
            if selected.count == 3 { break }
        }

        guard !selected.isEmpty else { throw IndependentRoutePlanningError.noRoutes }
        return selected.map(\.candidate)
    }

    private func evaluate(
        attempts: [CandidateAttempt],
        request: RoutePlanRequest
    ) async throws -> [EvaluatedCandidate] {
        var values: [AttemptResult] = []

        for batchStart in stride(from: 0, to: attempts.count, by: Self.concurrentAttemptLimit) {
            try Task.checkCancellation()
            let batchEnd = min(batchStart + Self.concurrentAttemptLimit, attempts.count)
            let batch = Array(attempts[batchStart..<batchEnd])
            let results = try await withThrowingTaskGroup(of: AttemptResult.self) { group in
                for attempt in batch {
                    group.addTask {
                        AttemptResult(
                            index: attempt.index,
                            evaluation: try await evaluate(attempt: attempt, request: request)
                        )
                    }
                }

                var batchValues: [AttemptResult] = []
                for try await value in group {
                    batchValues.append(value)
                }
                return batchValues
            }
            values.append(contentsOf: results)
        }

        return values
            .sorted { $0.index < $1.index }
            .compactMap(\.evaluation)
    }

    private func evaluate(
        attempt: CandidateAttempt,
        request: RoutePlanRequest
    ) async throws -> EvaluatedCandidate? {
        guard let anchors = try await validatedAnchors(for: attempt, request: request) else { return nil }

        let roadRoute: RoadRoute
        do {
            roadRoute = try await roadProvider.route(through: anchors)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }

        let distanceKm = roadRoute.distanceMeters / 1_000
        let deviation: Double
        let tolerance: Double
        if let requestedDistance = request.targetDistanceKm {
            deviation = relativeDifference(distanceKm, requestedDistance)
            tolerance = Self.explicitDistanceTolerance
        } else {
            deviation = relativeDifference(roadRoute.expectedTravelTime, request.targetDuration)
            tolerance = Self.timeTolerance
        }
        guard deviation <= tolerance else { return nil }

        let preview = roadRoute.coordinates.decimated(maxCount: 1_600)
        let character = characterAnalyzer.assess(
            coordinates: preview,
            context: roadRoute.context,
            mood: request.mood
        )
        let departure = CompassDirection.nearest(to: attempt.initialBearing)
        let targetDescription = request.targetDistanceKm.map { "\(Int($0.rounded())) km target" }
            ?? "\(request.time.title) target"
        let candidate = RouteCandidate(
            title: "\(request.mood.title) \(departure.title) \(attempt.titleSuffix)",
            distanceKm: distanceKm,
            durationSeconds: roadRoute.expectedTravelTime,
            time: formattedDuration(roadRoute.expectedTravelTime),
            elevationM: roadRoute.context.elevationGainMeters,
            summary: "\(targetDescription) · \(departure.title.lowercased()) departure",
            preview: preview,
            waypoints: anchors,
            character: character
        )
        let intentFit = max(1 - deviation / tolerance, 0)
        return EvaluatedCandidate(
            attemptIndex: attempt.index,
            candidate: candidate,
            selectionScore: Double(character.score) + intentFit * 200
        )
    }

    private func validatedAnchors(
        for attempt: CandidateAttempt,
        request: RoutePlanRequest
    ) async throws -> [Coordinate]? {
        var generator = SeededRouteRandomNumberGenerator(seed: attempt.anchorSeed)
        var anchors = [request.start]
        var current = request.start
        let segmentCount = Double(attempt.anchorCount + 1)
        let nominalLegKm = request.effectiveTargetDistanceKm * attempt.distanceScale / segmentCount
        let turnStep = 360 / segmentCount

        for anchorIndex in 0..<attempt.anchorCount {
            try Task.checkCancellation()
            let baseBearing = attempt.initialBearing + Double(anchorIndex) * turnStep
            var validated: Coordinate?

            for retry in 0..<Self.anchorRetryLimit {
                try Task.checkCancellation()
                let firstLegHasDirection = anchorIndex == 0 && request.direction != nil
                let bearingJitter = firstLegHasDirection
                    ? generator.double(in: -3...3)
                    : generator.double(in: -18...18)
                let retryJitter = retry == 0 ? 0 : generator.double(in: -16...16)
                let legScale = generator.double(in: 0.84...1.16)
                let proposed = current.projected(
                    distanceKm: max(nominalLegKm * legScale, 1.2),
                    bearingDegrees: baseBearing + bearingJitter + retryJitter
                )

                do {
                    let snapped = try await roadProvider.validatedAnchor(proposed, from: current)
                    if anchorIndex == 0, let direction = request.direction {
                        let snappedBearing = bearing(from: request.start, to: snapped)
                        guard angularDifference(snappedBearing, direction.bearingDegrees) <= 22.5 else {
                            continue
                        }
                    }
                    validated = snapped
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    continue
                }
            }

            guard let validated else { return nil }
            anchors.append(validated)
            current = validated
        }

        anchors.append(request.start)
        return anchors
    }

    private func candidateAttempts(for request: RoutePlanRequest, seed: UInt64) -> [CandidateAttempt] {
        var generator = SeededRouteRandomNumberGenerator(seed: seed)
        let distanceScales = [0.72, 0.82, 0.92, 1.02, 1.12]
        let suffixes = ["Loop", "Circuit", "Arc", "Roam"]

        return (0..<Self.attemptCount).map { index in
            let initialBearing: Double
            if let direction = request.direction {
                initialBearing = direction.bearingDegrees + generator.double(in: -16...16)
            } else {
                initialBearing = generator.double(in: 0..<360) + request.mood.bearingBias
            }
            let scale = distanceScales[index % distanceScales.count] * generator.double(in: 0.96...1.04)
            return CandidateAttempt(
                index: index,
                anchorCount: generator.integer(in: 3...6),
                distanceScale: scale,
                initialBearing: normalizedBearing(initialBearing),
                anchorSeed: generator.next(),
                titleSuffix: suffixes[index % suffixes.count]
            )
        }
    }

    private func runSeed() -> UInt64 {
        if let randomSeed { return randomSeed }
        var generator = SystemRandomNumberGenerator()
        return generator.next()
    }

    private func relativeDifference(_ value: Double, _ target: Double) -> Double {
        guard target > 0 else { return 1 }
        return abs(value - target) / target
    }

    private func bearing(from: Coordinate, to: Coordinate) -> Double {
        let startLatitude = from.latitude * .pi / 180
        let endLatitude = to.latitude * .pi / 180
        let deltaLongitude = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(deltaLongitude)
        return normalizedBearing(atan2(y, x) * 180 / .pi)
    }

    private func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }

    private func normalizedBearing(_ bearing: Double) -> Double {
        let value = bearing.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded()), 1)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

private struct CandidateAttempt: Sendable {
    let index: Int
    let anchorCount: Int
    let distanceScale: Double
    let initialBearing: Double
    let anchorSeed: UInt64
    let titleSuffix: String
}

private struct EvaluatedCandidate: Sendable {
    let attemptIndex: Int
    let candidate: RouteCandidate
    let selectionScore: Double
}

private struct AttemptResult: Sendable {
    let index: Int
    let evaluation: EvaluatedCandidate?
}

struct RoutePolylineOverlap {
    private static let cellSizeMeters = 250.0

    static func sharedFraction(_ first: [Coordinate], _ second: [Coordinate]) -> Double {
        let firstCells = cells(for: first)
        let secondCells = cells(for: second)
        let denominator = min(firstCells.count, secondCells.count)
        guard denominator > 0 else { return 0 }
        return Double(firstCells.intersection(secondCells).count) / Double(denominator)
    }

    private static func cells(for coordinates: [Coordinate]) -> Set<RouteGridCell> {
        Set(coordinates.map { coordinate in
            let latitudeRadians = coordinate.latitude * .pi / 180
            let northing = coordinate.latitude * 111_000
            let easting = coordinate.longitude * 111_000 * cos(latitudeRadians)
            return RouteGridCell(
                x: Int((easting / cellSizeMeters).rounded(.down)),
                y: Int((northing / cellSizeMeters).rounded(.down))
            )
        })
    }
}

private struct RouteGridCell: Hashable {
    let x: Int
    let y: Int
}

private struct SeededRouteRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func double(in range: Range<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        double(in: range.lowerBound..<range.upperBound)
    }

    mutating func integer(in range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }
}

private extension CompassDirection {
    static func nearest(to bearing: Double) -> CompassDirection {
        let normalized = bearing.truncatingRemainder(dividingBy: 360)
        let positive = normalized >= 0 ? normalized : normalized + 360
        let index = Int(((positive + 22.5) / 45).rounded(.down)) % allCases.count
        return allCases[index]
    }
}
