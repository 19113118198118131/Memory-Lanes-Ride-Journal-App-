import CoreLocation
import XCTest
@testable import MemoryLanes

final class RouteFollowAnalyzerTests: XCTestCase {
    private let analyzer = RouteFollowAnalyzer()

    func testProgressUsesPositionAlongRoute() {
        let route = plannedRoute([
            Coordinate(latitude: -36.85, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.77),
            Coordinate(latitude: -36.85, longitude: 174.78)
        ])
        let point = recordingPoint(latitude: -36.85, longitude: 174.77)

        let snapshot = analyzer.snapshot(route: route, recordedPoints: [point], distanceMeters: 900)

        XCTAssertEqual(snapshot.progressPercent, 50, accuracy: 5)
        XCTAssertLessThan(snapshot.currentDeviationMeters ?? .infinity, 5)
        XCTAssertEqual(snapshot.status, "On route")
    }

    func testOffRouteGuidancePointsBackToPlan() {
        let route = plannedRoute([
            Coordinate(latitude: -36.85, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.78)
        ])
        let point = recordingPoint(latitude: -36.84, longitude: 174.77)

        let snapshot = analyzer.snapshot(route: route, recordedPoints: [point], distanceMeters: 500)

        XCTAssertEqual(snapshot.status, "Off route")
        XCTAssertEqual(snapshot.guidanceTitle, "Return to route")
        XCTAssertGreaterThan(snapshot.currentDeviationMeters ?? 0, 900)
    }

    func testLoopFinishDoesNotSnapBackToStart() {
        let coordinates = [
            Coordinate(latitude: -36.85, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.77),
            Coordinate(latitude: -36.84, longitude: 174.77),
            Coordinate(latitude: -36.84, longitude: 174.76),
            Coordinate(latitude: -36.85, longitude: 174.76)
        ]
        let route = plannedRoute(coordinates)
        let point = recordingPoint(latitude: -36.84999, longitude: 174.76)
        let routeDistanceMeters = (route.distanceKm ?? 0) * 1_000

        let snapshot = analyzer.snapshot(
            route: route,
            recordedPoints: [point],
            distanceMeters: routeDistanceMeters - 5
        )

        XCTAssertGreaterThan(snapshot.progressPercent, 95)
        XCTAssertEqual(snapshot.guidanceTitle, "Finish ahead")
    }

    private func plannedRoute(_ coordinates: [Coordinate]) -> PlannedRoute {
        PlannedRoute(
            id: UUID(),
            title: "Test Route",
            distanceKm: coordinates.distanceKm,
            elevationM: 0,
            waypoints: coordinates,
            route: coordinates,
            createdAt: Date(),
            isPublic: false,
            shareToken: nil
        )
    }

    private func recordingPoint(latitude: Double, longitude: Double) -> RecordingPoint {
        RecordingPoint(
            location: CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 0,
                speed: 10,
                timestamp: Date()
            )
        )
    }
}

private extension Array where Element == Coordinate {
    var distanceKm: Double {
        guard count > 1 else { return 0 }
        return zip(self, dropFirst()).reduce(0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)) / 1_000
        }
    }
}
