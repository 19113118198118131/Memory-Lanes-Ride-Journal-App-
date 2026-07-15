import Foundation
import MapKit

protocol RoadRouteProviding: Sendable {
    func route(through waypoints: [Coordinate]) async throws -> RoadRoute
    func validatedAnchor(_ coordinate: Coordinate, from origin: Coordinate) async throws -> Coordinate
}

extension RoadRouteProviding {
    func validatedAnchor(_ coordinate: Coordinate, from _: Coordinate) async throws -> Coordinate {
        coordinate
    }
}

struct MapKitRoadRouteProvider: RoadRouteProviding {
    static let requestBudget = 44

    private let cache: MapKitRoadLegCache
    private let requestGate: MapKitDirectionsRequestGate

    init(
        cache: MapKitRoadLegCache = MapKitRoadLegCache(),
        requestGate: MapKitDirectionsRequestGate = MapKitDirectionsRequestGate()
    ) {
        self.cache = cache
        self.requestGate = requestGate
    }

    func validatedAnchor(_ coordinate: Coordinate, from origin: Coordinate) async throws -> Coordinate {
        try Task.checkCancellation()
        guard CLLocationCoordinate2DIsValid(coordinate.clCoordinate),
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude) else {
            throw IndependentRoutePlanningError.noRoutes
        }

        // Route the proposed leg now so water and other unroutable anchors can be
        // jittered by the planner. The result is cached and reused during assembly.
        _ = try await leg(from: origin, to: coordinate)
        return coordinate
    }

    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        guard waypoints.count > 1 else { throw IndependentRoutePlanningError.noRoutes }
        var coordinates: [Coordinate] = []
        var distanceMeters: Double = 0
        var expectedTravelTime: TimeInterval = 0

        for index in waypoints.indices.dropLast() {
            try Task.checkCancellation()
            let leg = try await leg(from: waypoints[index], to: waypoints[index + 1])
            let legCoordinates = leg.coordinates
            if let previousEnd = coordinates.last,
               let nextStart = legCoordinates.first,
               !RoadRouteGeometryValidator.canJoin(previousEnd, nextStart) {
                throw IndependentRoutePlanningError.noRoutes
            }
            coordinates.append(contentsOf: coordinates.isEmpty ? legCoordinates : Array(legCoordinates.dropFirst()))
            distanceMeters += leg.distanceMeters
            expectedTravelTime += leg.expectedTravelTime
        }

        guard coordinates.count > 1 else { throw IndependentRoutePlanningError.noRoutes }
        return RoadRoute(
            coordinates: coordinates,
            distanceMeters: distanceMeters,
            expectedTravelTime: expectedTravelTime,
            context: .geometryOnly
        )
    }

    private func leg(from source: Coordinate, to destination: Coordinate) async throws -> RoadRoute {
        let key = MapKitRoadLegKey(source: source, destination: destination)
        if let cached = await cache.value(for: key) { return cached }

        try await requestGate.beginRequest()
        let request = MKDirections.Request()
        request.source = mapItem(for: source)
        request.destination = mapItem(for: destination)
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        let response: MKDirections.Response
        do {
            response = try await MKDirections(request: request).calculate()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw error
        }
        guard let route = response.routes.first(where: { route in
            !Self.containsFerry(route) && RoadRouteGeometryValidator.isPlausibleLeg(
                route.polyline.memoryLanesCoordinates,
                source: source,
                destination: destination
            )
        }) else {
            throw IndependentRoutePlanningError.noRoutes
        }

        let value = RoadRoute(
            coordinates: route.polyline.memoryLanesCoordinates,
            distanceMeters: route.distance,
            expectedTravelTime: route.expectedTravelTime,
            context: .geometryOnly
        )
        await cache.store(value, for: key)
        return value
    }

    private func mapItem(for coordinate: Coordinate) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clCoordinate))
    }

    private static func containsFerry(_ route: MKRoute) -> Bool {
        let notices = route.advisoryNotices
        let stepText = route.steps.flatMap { step in
            [step.instructions, step.notice ?? ""]
        }
        return (notices + stepText).contains { value in
            value.localizedCaseInsensitiveContains("ferry")
        } || route.steps.contains { $0.transportType == .transit }
    }
}

struct MapKitRoadLegKey: Hashable, Sendable {
    let source: Coordinate
    let destination: Coordinate
}

actor MapKitRoadLegCache {
    private static let capacity = 96
    private var values: [MapKitRoadLegKey: RoadRoute] = [:]
    private var insertionOrder: [MapKitRoadLegKey] = []

    func value(for key: MapKitRoadLegKey) -> RoadRoute? {
        values[key]
    }

    func store(_ value: RoadRoute, for key: MapKitRoadLegKey) {
        if values[key] == nil { insertionOrder.append(key) }
        values[key] = value

        while insertionOrder.count > Self.capacity {
            let expired = insertionOrder.removeFirst()
            values.removeValue(forKey: expired)
        }
    }
}

actor MapKitDirectionsRequestGate {
    private static let window: TimeInterval = 60
    private var requestDates: [Date] = []

    func beginRequest(now: Date = Date()) throws {
        requestDates.removeAll { now.timeIntervalSince($0) >= Self.window }
        guard requestDates.count < MapKitRoadRouteProvider.requestBudget else {
            throw IndependentRoutePlanningError.requestLimitReached
        }
        requestDates.append(now)
    }
}

struct RoadRouteGeometryValidator {
    private static let maximumAnchorSnapMeters = 5_000.0
    private static let maximumJoinGapMeters = 250.0
    private static let maximumPolylineGapMeters = 5_000.0

    static func isPlausibleLeg(
        _ coordinates: [Coordinate],
        source: Coordinate,
        destination: Coordinate
    ) -> Bool {
        guard coordinates.count > 1,
              let first = coordinates.first,
              let last = coordinates.last,
              distanceMeters(first, source) <= maximumAnchorSnapMeters,
              distanceMeters(last, destination) <= maximumAnchorSnapMeters else {
            return false
        }
        return zip(coordinates, coordinates.dropFirst()).allSatisfy {
            distanceMeters($0.0, $0.1) <= maximumPolylineGapMeters
        }
    }

    static func canJoin(_ first: Coordinate, _ second: Coordinate) -> Bool {
        distanceMeters(first, second) <= maximumJoinGapMeters
    }

    private static func distanceMeters(_ first: Coordinate, _ second: Coordinate) -> Double {
        CLLocation(
            latitude: first.latitude,
            longitude: first.longitude
        ).distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
    }
}

struct RoadRoutePlanner: Sendable {
    private let provider: any RoadRouteProviding

    init(provider: any RoadRouteProviding = OfflineFirstRoadRouteProvider()) {
        self.provider = provider
    }

    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        try await provider.route(through: waypoints)
    }
}

private extension MKPolyline {
    var memoryLanesCoordinates: [Coordinate] {
        guard pointCount > 0 else { return [] }
        var values = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: pointCount
        )
        getCoordinates(&values, range: NSRange(location: 0, length: pointCount))
        return values.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

extension Array where Element == Coordinate {
    func decimated(maxCount: Int) -> [Coordinate] {
        guard maxCount > 1, count > maxCount else { return self }
        let interval = Double(count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { index in
            self[Int((Double(index) * interval).rounded())]
        }
    }
}

extension Coordinate {
    func projected(distanceKm: Double, bearingDegrees: Double) -> Coordinate {
        let earthRadiusKm = 6_371.0
        let angularDistance = distanceKm / earthRadiusKm
        let bearing = bearingDegrees * .pi / 180
        let startLatitude = latitude * .pi / 180
        let startLongitude = longitude * .pi / 180
        let endLatitude = asin(
            sin(startLatitude) * cos(angularDistance) +
            cos(startLatitude) * sin(angularDistance) * cos(bearing)
        )
        let endLongitude = startLongitude + atan2(
            sin(bearing) * sin(angularDistance) * cos(startLatitude),
            cos(angularDistance) - sin(startLatitude) * sin(endLatitude)
        )
        return Coordinate(
            latitude: endLatitude * 180 / .pi,
            longitude: endLongitude * 180 / .pi
        )
    }
}
