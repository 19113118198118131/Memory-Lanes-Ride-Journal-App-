import Foundation
import MapKit

protocol TurnByTurnRouteProviding: Sendable {
    func route(through waypoints: [Coordinate]) async throws -> TurnByTurnRoute
}

struct MapKitTurnByTurnRouteProvider: TurnByTurnRouteProviding {
    private let requestGate: MapKitDirectionsRequestGate

    init(requestGate: MapKitDirectionsRequestGate = MapKitDirectionsRequestGate()) {
        self.requestGate = requestGate
    }

    func route(through waypoints: [Coordinate]) async throws -> TurnByTurnRoute {
        guard waypoints.count > 1 else { throw TurnByTurnNavigationError.invalidRoute }
        var coordinates: [Coordinate] = []
        var instructions: [NavigationInstruction] = []
        var distanceMeters = 0.0
        var expectedTravelTime: TimeInterval = 0

        for index in waypoints.indices.dropLast() {
            try Task.checkCancellation()
            let leg = try await route(from: waypoints[index], to: waypoints[index + 1])
            let legCoordinates = leg.polyline.navigationCoordinates
            guard legCoordinates.count > 1 else { throw TurnByTurnNavigationError.noRoute }
            if let previous = coordinates.last,
               let next = legCoordinates.first,
               !RoadRouteGeometryValidator.canJoin(previous, next) {
                throw TurnByTurnNavigationError.noRoute
            }

            coordinates.append(contentsOf: coordinates.isEmpty ? legCoordinates : Array(legCoordinates.dropFirst()))
            var stepCursor = distanceMeters
            for step in leg.steps {
                let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    instructions.append(
                        NavigationInstruction(
                            id: instructions.count,
                            text: text,
                            notice: step.notice?.trimmingCharacters(in: .whitespacesAndNewlines),
                            maneuver: NavigationManeuverClassifier.classify(text),
                            startsAtMeters: stepCursor
                        )
                    )
                }
                stepCursor += max(step.distance, 0)
            }
            distanceMeters += leg.distance
            expectedTravelTime += leg.expectedTravelTime
        }

        guard coordinates.count > 1 else { throw TurnByTurnNavigationError.noRoute }
        if instructions.isEmpty {
            instructions.append(
                NavigationInstruction(
                    id: 0,
                    text: "Continue on the planned route",
                    notice: nil,
                    maneuver: .straight,
                    startsAtMeters: 0
                )
            )
        }
        instructions.append(
            NavigationInstruction(
                id: instructions.count,
                text: "Arrive at your destination",
                notice: nil,
                maneuver: .arrive,
                startsAtMeters: distanceMeters
            )
        )

        return TurnByTurnRoute(
            coordinates: coordinates,
            distanceMeters: distanceMeters,
            expectedTravelTime: expectedTravelTime,
            instructions: instructions
        )
    }

    private func route(from source: Coordinate, to destination: Coordinate) async throws -> MKRoute {
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
            throw TurnByTurnNavigationError.noRoute
        }
        guard let route = response.routes.first(where: { candidate in
            !Self.containsFerry(candidate) && RoadRouteGeometryValidator.isPlausibleLeg(
                candidate.polyline.navigationCoordinates,
                source: source,
                destination: destination
            )
        }) else {
            throw TurnByTurnNavigationError.noRoute
        }
        return route
    }

    private func mapItem(for coordinate: Coordinate) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clCoordinate))
    }

    private static func containsFerry(_ route: MKRoute) -> Bool {
        let stepText = route.steps.flatMap { [$0.instructions, $0.notice ?? ""] }
        return (route.advisoryNotices + stepText).contains {
            $0.localizedCaseInsensitiveContains("ferry")
        } || route.steps.contains { $0.transportType == .transit }
    }
}

enum NavigationManeuverClassifier {
    static func classify(_ instruction: String) -> NavigationManeuver {
        let value = instruction.lowercased()
        if value.contains("destination") || value.contains("arrive") { return .arrive }
        if value.contains("roundabout") || value.contains("traffic circle") { return .roundabout }
        if value.contains("u-turn") || value.contains("u turn") {
            return value.contains("right") ? .uTurnRight : .uTurnLeft
        }
        if value.contains("exit") && value.contains("left") { return .exitLeft }
        if value.contains("exit") && value.contains("right") { return .exitRight }
        if value.contains("keep left") { return .keepLeft }
        if value.contains("keep right") { return .keepRight }
        if value.contains("slight left") { return .slightLeft }
        if value.contains("slight right") { return .slightRight }
        if value.contains("sharp left") { return .sharpLeft }
        if value.contains("sharp right") { return .sharpRight }
        if value.contains("left") { return .left }
        if value.contains("right") { return .right }
        if value.contains("merge") { return .merge }
        if value.contains("start") || value.contains("head ") { return .start }
        return .straight
    }
}

private extension MKPolyline {
    var navigationCoordinates: [Coordinate] {
        guard pointCount > 0 else { return [] }
        var values = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: pointCount
        )
        getCoordinates(&values, range: NSRange(location: 0, length: pointCount))
        return values.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
