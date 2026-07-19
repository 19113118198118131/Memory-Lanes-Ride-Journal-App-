import Foundation

struct OfflineNavigationPath: Sendable {
    let route: RoadRoute
    let edges: [OfflineRoadEdge]
}

struct OfflineRoadRouteProvider: RoadRouteProviding {
    private let regionStore: any OfflineRegionServing
    private let graphLoader: any OfflineRoadGraphLoading
    private let pathfinder: OfflineRoadPathfinder
    private let telemetry: any OfflineRoutingTelemetryServing
    private let maximumSnapDistanceMeters: Double

    init(
        regionStore: any OfflineRegionServing = OfflineRegionStore.shared,
        graphLoader: any OfflineRoadGraphLoading = OfflineRoadGraphLoader.shared,
        pathfinder: OfflineRoadPathfinder = OfflineRoadPathfinder(),
        telemetry: any OfflineRoutingTelemetryServing = OfflineRoutingTelemetryStore.shared,
        maximumSnapDistanceMeters: Double = 5_000
    ) {
        self.regionStore = regionStore
        self.graphLoader = graphLoader
        self.pathfinder = pathfinder
        self.telemetry = telemetry
        self.maximumSnapDistanceMeters = maximumSnapDistanceMeters
    }

    func validatedAnchor(_ coordinate: Coordinate, from origin: Coordinate) async throws -> Coordinate {
        let result = try await routeAndSnaps(
            through: [origin, coordinate],
            operation: .anchorValidation
        )
        guard let destination = result.snaps.last else { throw OfflineRoadRoutingError.cannotSnap }
        return destination.coordinate
    }

    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        try await routeAndSnaps(through: waypoints, operation: .route).route
    }

    func navigationPath(through waypoints: [Coordinate]) async throws -> OfflineNavigationPath {
        let result = try await routeAndSnaps(through: waypoints, operation: .route)
        return OfflineNavigationPath(route: result.route, edges: result.edges)
    }

    private func routeAndSnaps(
        through waypoints: [Coordinate],
        operation: OfflineRoutingOperation
    ) async throws -> (
        route: RoadRoute,
        snaps: [OfflineRoadSnap],
        edges: [OfflineRoadEdge]
    ) {
        let startedAt = Date()
        var selectedGraph: InstalledOfflineRoadGraph?
        do {
            guard waypoints.count > 1 else { throw OfflineRoadRoutingError.noPath }
            let installation = try await commonGraph(for: waypoints)
            selectedGraph = installation
            let graph = try await graphLoader.graph(at: installation.fileURL)
            let candidates = waypoints.map { coordinate in
                graph.nearestNodesByWeakComponent(
                    to: coordinate,
                    maximumDistanceMeters: maximumSnapDistanceMeters
                )
            }
            let snaps = try connectedSnaps(from: candidates)

            var coordinates: [Coordinate] = []
            var edges: [OfflineRoadEdge] = []
            var distanceMeters: Double = 0
            var expectedTravelTime: TimeInterval = 0
            for index in snaps.indices.dropLast() {
                try Task.checkCancellation()
                let leg = try pathfinder.path(
                    in: graph,
                    from: snaps[index].nodeID,
                    to: snaps[index + 1].nodeID
                )
                coordinates.append(contentsOf: coordinates.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
                edges.append(contentsOf: leg.edges)
                distanceMeters += leg.distanceMeters
                expectedTravelTime += leg.expectedTravelTime
            }
            guard coordinates.count > 1 else { throw OfflineRoadRoutingError.noPath }
            let route = RoadRoute(
                coordinates: coordinates,
                distanceMeters: distanceMeters,
                expectedTravelTime: expectedTravelTime,
                context: roadContext(for: edges)
            )
            await telemetry.record(telemetryEvent(
                operation: operation,
                outcome: .localSuccess,
                installation: installation,
                startedAt: startedAt
            ))
            return (route, snaps, edges)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await telemetry.record(telemetryEvent(
                operation: operation,
                outcome: .fallback(OfflineRoutingFallbackReason(error: error)),
                installation: selectedGraph,
                startedAt: startedAt
            ))
            throw error
        }
    }

    private func telemetryEvent(
        operation: OfflineRoutingOperation,
        outcome: OfflineRoutingTelemetryEvent.Outcome,
        installation: InstalledOfflineRoadGraph?,
        startedAt: Date
    ) -> OfflineRoutingTelemetryEvent {
        OfflineRoutingTelemetryEvent(
            occurredAt: Date(),
            operation: operation,
            outcome: outcome,
            regionID: installation?.regionID,
            regionName: installation?.regionName,
            regionVersion: installation?.version,
            durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
    }

    private func connectedSnaps(
        from candidates: [[UInt64: OfflineRoadSnap]]
    ) throws -> [OfflineRoadSnap] {
        guard var commonComponents = candidates.first.map({ Set($0.keys) }),
              !commonComponents.isEmpty else {
            throw OfflineRoadRoutingError.cannotSnap
        }
        for options in candidates.dropFirst() {
            commonComponents.formIntersection(options.keys)
        }
        guard !commonComponents.isEmpty else { throw OfflineRoadRoutingError.noPath }

        var best: (distance: Double, snaps: [OfflineRoadSnap])?
        for componentID in commonComponents {
            let snaps = candidates.compactMap { $0[componentID] }
            guard snaps.count == candidates.count else { continue }
            let distance = snaps.reduce(0) { $0 + $1.distanceMeters }
            if best.map({ distance < $0.distance }) ?? true {
                best = (distance, snaps)
            }
        }
        guard let best else { throw OfflineRoadRoutingError.noPath }
        return best.snaps
    }

    private func commonGraph(for waypoints: [Coordinate]) async throws -> InstalledOfflineRoadGraph {
        var selectedGraph: InstalledOfflineRoadGraph?
        for waypoint in waypoints {
            try Task.checkCancellation()
            guard let graph = await regionStore.localGraph(containing: waypoint) else {
                throw OfflineRoadRoutingError.noCoverage
            }
            if let selectedGraph, selectedGraph.fileURL != graph.fileURL {
                throw OfflineRoadRoutingError.noCoverage
            }
            selectedGraph = graph
        }
        guard let selectedGraph else { throw OfflineRoadRoutingError.noCoverage }
        return selectedGraph
    }

    private func roadContext(for edges: [OfflineRoadEdge]) -> RouteRoadContext {
        let totalDistance = edges.reduce(0) { $0 + $1.distanceMeters }
        guard totalDistance > 0 else { return .geometryOnly }
        let motorwayDistance = edges
            .filter { $0.roadClass == .motorway }
            .reduce(0) { $0 + $1.distanceMeters }
        let unsuitableSurfaces = Set([
            "dirt", "earth", "grass", "gravel", "ground", "mud", "sand", "unpaved"
        ])
        let unsuitableDistance = edges
            .filter { edge in edge.surface.map { unsuitableSurfaces.contains($0.lowercased()) } ?? false }
            .reduce(0) { $0 + $1.distanceMeters }
        return RouteRoadContext(
            motorwayRatio: motorwayDistance / totalDistance,
            unsuitableSurfaceRatio: unsuitableDistance / totalDistance
        )
    }
}

struct OfflineFirstRoadRouteProvider: RoadRouteProviding {
    private let offline: any RoadRouteProviding
    private let fallback: any RoadRouteProviding

    init(
        offline: any RoadRouteProviding = OfflineRoadRouteProvider(),
        fallback: any RoadRouteProviding = MapKitRoadRouteProvider()
    ) {
        self.offline = offline
        self.fallback = fallback
    }

    func validatedAnchor(_ coordinate: Coordinate, from origin: Coordinate) async throws -> Coordinate {
        do {
            return try await offline.validatedAnchor(coordinate, from: origin)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.validatedAnchor(coordinate, from: origin)
        }
    }

    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        do {
            return try await offline.route(through: waypoints)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.route(through: waypoints)
        }
    }
}
