import Foundation
import MapKit

protocol RoadRouteProviding: Sendable {
    func route(through waypoints: [Coordinate]) async throws -> RoadRoute
}

struct MapKitRoadRouteProvider: RoadRouteProviding {
    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        guard waypoints.count > 1 else { throw IndependentRoutePlanningError.noRoutes }
        var coordinates: [Coordinate] = []
        var distanceMeters: Double = 0
        var expectedTravelTime: TimeInterval = 0

        for index in waypoints.indices.dropLast() {
            try Task.checkCancellation()
            let request = MKDirections.Request()
            request.source = mapItem(for: waypoints[index])
            request.destination = mapItem(for: waypoints[index + 1])
            request.transportType = .automobile
            request.requestsAlternateRoutes = false

            let response: MKDirections.Response
            do {
                response = try await MKDirections(request: request).calculate()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw IndependentRoutePlanningError.noRoutes
            }
            guard let leg = response.routes.first else { throw IndependentRoutePlanningError.noRoutes }
            let legCoordinates = leg.polyline.memoryLanesCoordinates
            coordinates.append(contentsOf: coordinates.isEmpty ? legCoordinates : Array(legCoordinates.dropFirst()))
            distanceMeters += leg.distance
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

    private func mapItem(for coordinate: Coordinate) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clCoordinate))
    }
}

struct RoadRoutePlanner: Sendable {
    private let provider: any RoadRouteProviding

    init(provider: any RoadRouteProviding = MapKitRoadRouteProvider()) {
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
