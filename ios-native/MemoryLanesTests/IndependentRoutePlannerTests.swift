import Foundation
import Testing
@testable import MemoryLanes

struct IndependentRoutePlannerTests {
    private let start = Coordinate(latitude: -36.85, longitude: 174.76)

    @Test func plannerProducesRankedCandidatesWithoutAHostedRoutingDependency() async throws {
        let planner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 41)
        let candidates = try await planner.candidates(for: request(distanceKm: 72))

        #expect((3...6).contains(candidates.count))
        #expect(candidates.allSatisfy { $0.preview.count > 2 })
        #expect(candidates.allSatisfy { $0.character.confidence == .geometry })
    }

    @Test func seededGenerationIsDeterministic() async throws {
        let firstPlanner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 8_675_309)
        let secondPlanner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 8_675_309)

        let first = try await firstPlanner.candidates(for: request(distanceKm: 90))
        let second = try await secondPlanner.candidates(for: request(distanceKm: 90))

        #expect(first.map(\.title) == second.map(\.title))
        #expect(first.map(\.waypoints) == second.map(\.waypoints))
        #expect(first.map(\.preview) == second.map(\.preview))
        #expect(first.map(\.distanceKm) == second.map(\.distanceKm))
    }

    @Test func aNewSeedProducesFreshRouteGeometry() async throws {
        let firstPlanner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 101)
        let secondPlanner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 202)

        let first = try await firstPlanner.candidates(for: request(distanceKm: 90))
        let second = try await secondPlanner.candidates(for: request(distanceKm: 90))

        #expect(first.map(\.waypoints) != second.map(\.waypoints))
    }

    @Test func selectedCandidatesRespectDiversityConstraint() async throws {
        let planner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 4_242)
        let candidates = try await planner.candidates(for: request(distanceKm: 80))

        #expect(candidates.count >= 3)
        for firstIndex in candidates.indices {
            for secondIndex in candidates.indices where secondIndex > firstIndex {
                let overlap = RoutePolylineOverlap.sharedFraction(
                    candidates[firstIndex].preview,
                    candidates[secondIndex].preview
                )
                #expect(overlap <= IndependentRoutePlanner.diversityOverlapLimit)
            }
        }
    }

    @Test func explicitDistanceOverrideIsRespectedWithinTolerance() async throws {
        let targetDistanceKm = 110.0
        let planner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 99)
        let candidates = try await planner.candidates(for: request(distanceKm: targetDistanceKm))

        let bestMatches = candidates.filter { $0.matchTier == .best }

        #expect(!bestMatches.isEmpty)
        #expect(bestMatches.allSatisfy {
            abs($0.distanceKm - targetDistanceKm) / targetDistanceKm <= 0.20
        })
        #expect(candidates.allSatisfy {
            abs($0.distanceKm - targetDistanceKm) / targetDistanceKm <= 0.50
        })
    }

    @Test func fortyFiveMinuteRequestRejectsGrosslyOverTimeRoutes() async throws {
        let planner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 314)
        let candidates = try await planner.candidates(for: RoutePlanRequest(
            mood: .relaxed,
            time: .fortyFive,
            start: start
        ))
        let targetDuration = RouteTime.fortyFive.hours * 60 * 60

        #expect(candidates.contains { $0.matchTier == .best })
        #expect(candidates.allSatisfy {
            abs($0.durationSeconds - targetDuration) / targetDuration <= 0.50
        })
        #expect(candidates.filter { $0.matchTier == .best }.allSatisfy {
            abs($0.durationSeconds - targetDuration) / targetDuration <= 0.20
        })
    }

    @Test func candidatesAreClassifiedByTheirTargetDeviation() async throws {
        let targetDistanceKm = 80.0
        let planner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 4_001)
        let candidates = try await planner.candidates(for: request(distanceKm: targetDistanceKm))

        #expect(!candidates.isEmpty)
        for candidate in candidates {
            let deviation = abs(candidate.distanceKm - targetDistanceKm) / targetDistanceKm
            switch candidate.matchTier {
            case .best: #expect(deviation <= 0.20)
            case .close: #expect(deviation > 0.20 && deviation <= 0.35)
            case .explore: #expect(deviation > 0.35 && deviation <= 0.50)
            }
            #expect(candidate.targetDeviation == deviation)
        }
    }

    @Test func aUsableDistantMatchIsKeptAsACollapsedAlternative() async throws {
        let planner = IndependentRoutePlanner(
            roadProvider: FixedDurationRoadProvider(minutes: 75),
            randomSeed: 7_575
        )
        let candidates = try await planner.candidates(for: RoutePlanRequest(
            mood: .relaxed,
            time: .fortyFive,
            start: start
        ))

        #expect(!candidates.isEmpty)
        #expect(candidates.allSatisfy { $0.matchTier == .explore })
        #expect(candidates.allSatisfy { $0.targetDeltaText == "+30 min" })
    }

    @Test func requestedDirectionBiasesFirstLegIntoCompassSector() async throws {
        let planner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 2_026)
        let candidates = try await planner.candidates(for: RoutePlanRequest(
            mood: .relaxed,
            time: .ninety,
            start: start,
            targetDistanceKm: 70,
            direction: .east
        ))

        #expect(!candidates.isEmpty)
        for candidate in candidates {
            let firstLegBearing = bearing(from: candidate.waypoints[0], to: candidate.waypoints[1])
            #expect(angularDifference(firstLegBearing, CompassDirection.east.bearingDegrees) <= 22.5)
        }
    }

    @Test func multipleDirectionsDistributeCandidatesAcrossAllowedSectors() async throws {
        let allowed: Set<CompassDirection> = [.north, .east]
        let planner = IndependentRoutePlanner(roadProvider: StubRoadProvider(), randomSeed: 2_027)
        let candidates = try await planner.candidates(for: RoutePlanRequest(
            primaryMood: .flowing,
            secondaryMood: .scenic,
            time: .ninety,
            start: start,
            targetDistanceKm: 75,
            directions: allowed
        ))

        #expect(!candidates.isEmpty)
        #expect(candidates.allSatisfy { candidate in
            let firstLegBearing = bearing(from: candidate.waypoints[0], to: candidate.waypoints[1])
            return allowed.contains { angularDifference(firstLegBearing, $0.bearingDegrees) <= 22.5 }
        })
        #expect(candidates.allSatisfy { $0.title.contains("Flowing + Scenic") })
    }

    @Test func failedAnchorValidationIsRetried() async throws {
        let probe = AnchorRetryProbe(failuresBeforeSuccess: 3)
        let planner = IndependentRoutePlanner(
            roadProvider: RetryingStubRoadProvider(probe: probe),
            randomSeed: 707
        )

        let candidates = try await planner.candidates(for: request(distanceKm: 75))
        let snapshot = await probe.snapshot()

        #expect(!candidates.isEmpty)
        #expect(snapshot.failures == 3)
        #expect(snapshot.validations > snapshot.failures)
    }

    @Test func anExhaustedFirstBatchRecoversWithFreshGeometry() async throws {
        let probe = RouteBatchRetryProbe(failuresBeforeSuccess: 15)
        let planner = IndependentRoutePlanner(
            roadProvider: RecoveringRoadProvider(probe: probe),
            randomSeed: 9_909
        )

        let candidates = try await planner.candidates(for: request(distanceKm: 80))
        let attempts = await probe.attemptCount

        #expect(!candidates.isEmpty)
        #expect(attempts > 15)
    }

    private func request(distanceKm: Double) -> RoutePlanRequest {
        RoutePlanRequest(
            mood: .twisty,
            time: .ninety,
            start: start,
            targetDistanceKm: distanceKm,
            direction: nil
        )
    }

    private func bearing(from: Coordinate, to: Coordinate) -> Double {
        let startLatitude = from.latitude * .pi / 180
        let endLatitude = to.latitude * .pi / 180
        let deltaLongitude = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(deltaLongitude)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }

    private func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }
}

private struct StubRoadProvider: RoadRouteProviding {
    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        let coordinates = zip(waypoints, waypoints.dropFirst()).flatMap { start, end in
            (0..<12).map { step in
                let progress = Double(step) / 12
                let bow = sin(progress * .pi) * 0.002
                return Coordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * progress + bow,
                    longitude: start.longitude + (end.longitude - start.longitude) * progress - bow
                )
            }
        } + Array(waypoints.suffix(1))
        let distance = coordinates.totalTestDistanceMeters
        return RoadRoute(
            coordinates: coordinates,
            distanceMeters: distance,
            expectedTravelTime: distance / 14,
            context: .geometryOnly
        )
    }
}

private struct RetryingStubRoadProvider: RoadRouteProviding {
    let probe: AnchorRetryProbe
    private let routeProvider = StubRoadProvider()

    func validatedAnchor(_ coordinate: Coordinate, from _: Coordinate) async throws -> Coordinate {
        if await probe.shouldFailValidation() {
            throw IndependentRoutePlanningError.noRoutes
        }
        return coordinate
    }

    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        try await routeProvider.route(through: waypoints)
    }
}

private struct RecoveringRoadProvider: RoadRouteProviding {
    let probe: RouteBatchRetryProbe
    private let routeProvider = StubRoadProvider()

    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        if await probe.shouldFail() {
            throw IndependentRoutePlanningError.noRoutes
        }
        return try await routeProvider.route(through: waypoints)
    }
}

private struct FixedDurationRoadProvider: RoadRouteProviding {
    let minutes: Double
    private let routeProvider = StubRoadProvider()

    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        let route = try await routeProvider.route(through: waypoints)
        return RoadRoute(
            coordinates: route.coordinates,
            distanceMeters: route.distanceMeters,
            expectedTravelTime: minutes * 60,
            context: route.context
        )
    }
}

private actor RouteBatchRetryProbe {
    private var remainingFailures: Int
    private(set) var attemptCount = 0

    init(failuresBeforeSuccess: Int) {
        remainingFailures = failuresBeforeSuccess
    }

    func shouldFail() -> Bool {
        attemptCount += 1
        guard remainingFailures > 0 else { return false }
        remainingFailures -= 1
        return true
    }
}

private actor AnchorRetryProbe {
    private var remainingFailures: Int
    private var validationCount = 0
    private var failureCount = 0

    init(failuresBeforeSuccess: Int) {
        remainingFailures = failuresBeforeSuccess
    }

    func shouldFailValidation() -> Bool {
        validationCount += 1
        guard remainingFailures > 0 else { return false }
        remainingFailures -= 1
        failureCount += 1
        return true
    }

    func snapshot() -> (validations: Int, failures: Int) {
        (validationCount, failureCount)
    }
}

private extension Array where Element == Coordinate {
    var totalTestDistanceMeters: Double {
        zip(self, dropFirst()).reduce(0) { total, pair in
            let latitudeMeters = (pair.1.latitude - pair.0.latitude) * 111_000
            let longitudeMeters = (pair.1.longitude - pair.0.longitude) * 88_000
            return total + hypot(latitudeMeters, longitudeMeters)
        }
    }
}
