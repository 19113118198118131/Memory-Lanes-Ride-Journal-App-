import Foundation

struct OfflineRoadRouteProvider: RoadRouteProviding {
    private let regionStore: any OfflineRegionServing
    private let graphLoader: any OfflineRoadGraphLoading
    private let pathfinder: OfflineRoadPathfinder
    private let maximumSnapDistanceMeters: Double

    init(
        regionStore: any OfflineRegionServing = OfflineRegionStore.shared,
        graphLoader: any OfflineRoadGraphLoading = OfflineRoadGraphLoader.shared,
        pathfinder: OfflineRoadPathfinder = OfflineRoadPathfinder(),
        maximumSnapDistanceMeters: Double = 5_000
    ) {
        self.regionStore = regionStore
        self.graphLoader = graphLoader
        self.pathfinder = pathfinder
        self.maximumSnapDistanceMeters = maximumSnapDistanceMeters
    }

    func validatedAnchor(_ coordinate: Coordinate, from origin: Coordinate) async throws -> Coordinate {
        let result = try await routeAndSnaps(through: [origin, coordinate])
        guard let destination = result.snaps.last else { throw OfflineRoadRoutingError.cannotSnap }
        return destination.coordinate
    }

    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        try await routeAndSnaps(through: waypoints).route
    }

    private func routeAndSnaps(through waypoints: [Coordinate]) async throws -> (
        route: RoadRoute,
        snaps: [OfflineRoadSnap]
    ) {
        guard waypoints.count > 1 else { throw OfflineRoadRoutingError.noPath }
        let graphURL = try await commonGraphURL(for: waypoints)
        let graph = try await graphLoader.graph(at: graphURL)
        let snaps = try waypoints.map { coordinate in
            guard let snap = graph.nearestNode(
                to: coordinate,
                maximumDistanceMeters: maximumSnapDistanceMeters
            ) else {
                throw OfflineRoadRoutingError.cannotSnap
            }
            return snap
        }

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
        return (
            RoadRoute(
                coordinates: coordinates,
                distanceMeters: distanceMeters,
                expectedTravelTime: expectedTravelTime,
                context: roadContext(for: edges)
            ),
            snaps
        )
    }

    private func commonGraphURL(for waypoints: [Coordinate]) async throws -> URL {
        var selectedURL: URL?
        for waypoint in waypoints {
            try Task.checkCancellation()
            guard let url = await regionStore.localGraphURL(containing: waypoint) else {
                throw OfflineRoadRoutingError.noCoverage
            }
            if let selectedURL, selectedURL != url {
                throw OfflineRoadRoutingError.noCoverage
            }
            selectedURL = url
        }
        guard let selectedURL else { throw OfflineRoadRoutingError.noCoverage }
        return selectedURL
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
