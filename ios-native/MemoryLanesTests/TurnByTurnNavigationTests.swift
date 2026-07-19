import XCTest
@testable import MemoryLanes

final class TurnByTurnNavigationTests: XCTestCase {
    func testProgressSelectsTheNextRoadInstruction() throws {
        let route = navigationRoute()
        var engine = try TurnByTurnNavigationEngine(route: route)

        let snapshot = engine.update(
            coordinate: Coordinate(latitude: -36.85, longitude: 174.7645)
        )

        XCTAssertEqual(snapshot.state, .onRoute)
        XCTAssertEqual(snapshot.instruction?.text, "Turn right onto Ridge Road")
        XCTAssertEqual(snapshot.instruction?.maneuver, .right)
        XCTAssertGreaterThan(snapshot.distanceToManeuverMeters ?? 0, 300)
        XCTAssertLessThan(snapshot.distanceToManeuverMeters ?? .infinity, 600)
        XCTAssertGreaterThan(snapshot.progressPercent, 15)
    }

    func testOffRouteLocationRequestsRecoveryWithoutLosingProgress() throws {
        var engine = try TurnByTurnNavigationEngine(route: navigationRoute())
        _ = engine.update(coordinate: Coordinate(latitude: -36.85, longitude: 174.768))

        let snapshot = engine.update(
            coordinate: Coordinate(latitude: -36.845, longitude: 174.768)
        )

        XCTAssertEqual(snapshot.state, .offRoute)
        XCTAssertEqual(snapshot.guidanceTitle, "Finding a safe return")
        XCTAssertGreaterThan(snapshot.deviationMeters ?? 0, 150)
        XCTAssertGreaterThan(snapshot.progressPercent, 25)
    }

    func testNoisyLocationCannotMoveNavigationProgressBackward() throws {
        var engine = try TurnByTurnNavigationEngine(route: navigationRoute())
        let forward = engine.update(
            coordinate: Coordinate(latitude: -36.85, longitude: 174.768)
        )
        let noisyRegression = engine.update(
            coordinate: Coordinate(latitude: -36.85, longitude: 174.765)
        )

        XCTAssertGreaterThan(forward.progressPercent, 25)
        XCTAssertEqual(noisyRegression.progressPercent, forward.progressPercent, accuracy: 0.01)
        XCTAssertEqual(
            noisyRegression.remainingDistanceMeters,
            forward.remainingDistanceMeters,
            accuracy: 1
        )
    }

    func testArrivalUsesDestinationDistanceAndETA() throws {
        let route = navigationRoute()
        var engine = try TurnByTurnNavigationEngine(route: route)

        let destination = try XCTUnwrap(route.coordinates.last)
        let snapshot = engine.update(coordinate: destination)

        XCTAssertEqual(snapshot.state, .arrived)
        XCTAssertEqual(snapshot.remainingDistanceMeters, 0, accuracy: 60)
        XCTAssertEqual(snapshot.remainingTravelTime, 0, accuracy: 10)
        XCTAssertEqual(snapshot.guidanceSymbol, "flag.checkered")
    }

    func testLoopProgressDoesNotSnapBackToStartAtTheFinish() throws {
        let coordinates = [
            Coordinate(latitude: -36.85, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.77),
            Coordinate(latitude: -36.84, longitude: 174.77),
            Coordinate(latitude: -36.84, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.76)
        ]
        let route = TurnByTurnRoute(
            coordinates: coordinates,
            distanceMeters: 4_000,
            expectedTravelTime: 300,
            instructions: [
                NavigationInstruction(id: 0, text: "Start route", notice: nil, maneuver: .start, startsAtMeters: 0),
                NavigationInstruction(id: 1, text: "Arrive", notice: nil, maneuver: .arrive, startsAtMeters: 4_000)
            ]
        )
        var engine = try TurnByTurnNavigationEngine(route: route)
        _ = engine.update(coordinate: coordinates[2])
        _ = engine.update(coordinate: coordinates[3])

        let finish = engine.update(coordinate: Coordinate(latitude: -36.84999, longitude: 174.76))

        XCTAssertGreaterThan(finish.progressPercent, 95)
        XCTAssertEqual(finish.state, .arrived)
    }

    func testRecoveryWaypointsReconnectAheadAndPreserveDestination() {
        let route = plannedRoute()
        let current = Coordinate(latitude: -36.848, longitude: 174.768)

        let recovery = NavigationRecoveryPlanner.waypoints(
            from: current,
            plannedRoute: route,
            progressPercent: 35
        )

        XCTAssertEqual(recovery.first, current)
        XCTAssertEqual(recovery.last, route.route.last)
        XCTAssertGreaterThanOrEqual(recovery.count, 3)
        XCTAssertNotEqual(recovery[1], route.route.first)
    }

    func testManeuverClassifierProducesGlanceableSymbols() {
        XCTAssertEqual(NavigationManeuverClassifier.classify("Turn sharp left onto Coast Road"), .sharpLeft)
        XCTAssertEqual(NavigationManeuverClassifier.classify("At the roundabout take the second exit"), .roundabout)
        XCTAssertEqual(NavigationManeuverClassifier.classify("Keep right to merge"), .keepRight)
        XCTAssertEqual(NavigationManeuverClassifier.classify("You have arrived at your destination"), .arrive)
    }

    func testOfflineManeuverBuilderCreatesNamedTurnInstructions() throws {
        let coordinates = [
            Coordinate(latitude: -36.85, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.77),
            Coordinate(latitude: -36.86, longitude: 174.77)
        ]
        let path = OfflineNavigationPath(
            route: RoadRoute(
                coordinates: coordinates,
                distanceMeters: 2_000,
                expectedTravelTime: 180,
                context: .geometryOnly
            ),
            edges: [
                offlineEdge(wayID: 10, source: 1, destination: 2, name: "Valley Road"),
                offlineEdge(wayID: 20, source: 2, destination: 3, name: "Ridge Road")
            ]
        )

        let route = try OfflineManeuverBuilder().route(from: path)

        XCTAssertEqual(route.instructions.map(\.maneuver), [.start, .right, .arrive])
        XCTAssertEqual(route.instructions[0].text, "Head east on Valley Road")
        XCTAssertEqual(route.instructions[1].text, "Turn right onto Ridge Road")
        XCTAssertEqual(route.instructions[1].startsAtMeters, 1_000)
    }

    func testOfflineManeuverBuilderSuppressesSameRoadBends() throws {
        let coordinates = [
            Coordinate(latitude: -36.85, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.77),
            Coordinate(latitude: -36.86, longitude: 174.77)
        ]
        let path = OfflineNavigationPath(
            route: RoadRoute(
                coordinates: coordinates,
                distanceMeters: 2_000,
                expectedTravelTime: 180,
                context: .geometryOnly
            ),
            edges: [
                offlineEdge(wayID: 10, source: 1, destination: 2, name: "Coast Road"),
                offlineEdge(wayID: 10, source: 2, destination: 3, name: "Coast Road")
            ]
        )

        let route = try OfflineManeuverBuilder().route(from: path)

        XCTAssertEqual(route.instructions.map(\.maneuver), [.start, .arrive])
    }

    func testOfflineFirstTurnByTurnProviderFallsBackWhenCoverageIsMissing() async throws {
        let expected = navigationRoute()
        let provider = OfflineFirstTurnByTurnRouteProvider(
            offline: ThrowingTurnByTurnProvider(),
            fallback: FixedTurnByTurnProvider(route: expected)
        )

        let route = try await provider.route(through: expected.coordinates)

        XCTAssertEqual(route, expected)
    }

    func testVoicePolicyAnnouncesEachDistanceThresholdOnce() {
        var policy = NavigationAnnouncementPolicy()
        let first = snapshot(distance: 950)
        let repeated = snapshot(distance: 900)
        let close = snapshot(distance: 250)
        let now = snapshot(distance: 60)

        XCTAssertEqual(policy.announcement(for: first), "In one kilometre, Turn right onto Ridge Road.")
        XCTAssertNil(policy.announcement(for: repeated))
        XCTAssertEqual(policy.announcement(for: close), "In 300 metres, Turn right onto Ridge Road.")
        XCTAssertEqual(policy.announcement(for: now), "Now, Turn right onto Ridge Road.")
    }

    private func navigationRoute() -> TurnByTurnRoute {
        let coordinates = [
            Coordinate(latitude: -36.85, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.77),
            Coordinate(latitude: -36.84, longitude: 174.77)
        ]
        return TurnByTurnRoute(
            coordinates: coordinates,
            distanceMeters: 2_000,
            expectedTravelTime: 180,
            instructions: [
                NavigationInstruction(id: 0, text: "Head east on Valley Road", notice: nil, maneuver: .start, startsAtMeters: 0),
                NavigationInstruction(id: 1, text: "Turn right onto Ridge Road", notice: nil, maneuver: .right, startsAtMeters: 900),
                NavigationInstruction(id: 2, text: "Arrive at your destination", notice: nil, maneuver: .arrive, startsAtMeters: 2_000)
            ]
        )
    }

    private func plannedRoute() -> PlannedRoute {
        let coordinates = [
            Coordinate(latitude: -36.85, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.77),
            Coordinate(latitude: -36.84, longitude: 174.77),
            Coordinate(latitude: -36.84, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.76)
        ]
        return PlannedRoute(
            id: UUID(),
            title: "Loop",
            distanceKm: 4,
            elevationM: 0,
            waypoints: coordinates,
            route: coordinates,
            createdAt: Date(),
            isPublic: false,
            shareToken: nil
        )
    }

    private func snapshot(distance: Double) -> TurnByTurnSnapshot {
        TurnByTurnSnapshot(
            state: .onRoute,
            instruction: NavigationInstruction(
                id: 1,
                text: "Turn right onto Ridge Road",
                notice: nil,
                maneuver: .right,
                startsAtMeters: 1_000
            ),
            upcomingInstruction: nil,
            distanceToManeuverMeters: distance,
            remainingDistanceMeters: 5_000,
            remainingTravelTime: 600,
            progressPercent: 40,
            deviationMeters: 5,
            matchedDistanceMeters: 4_000
        )
    }

    private func offlineEdge(
        wayID: UInt64,
        source: UInt64,
        destination: UInt64,
        name: String
    ) -> OfflineRoadEdge {
        OfflineRoadEdge(
            wayID: wayID,
            sourceNodeID: source,
            destinationNodeID: destination,
            distanceMeters: 1_000,
            expectedTravelTime: 90,
            roadClass: .secondary,
            name: name,
            surface: "asphalt",
            maximumSpeedKPH: 80
        )
    }
}

private struct ThrowingTurnByTurnProvider: TurnByTurnRouteProviding {
    func route(through _: [Coordinate]) async throws -> TurnByTurnRoute {
        throw OfflineRoadRoutingError.noCoverage
    }
}

private struct FixedTurnByTurnProvider: TurnByTurnRouteProviding {
    let route: TurnByTurnRoute

    func route(through _: [Coordinate]) async throws -> TurnByTurnRoute { route }
}
