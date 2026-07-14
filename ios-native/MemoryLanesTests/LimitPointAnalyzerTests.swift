import XCTest
@testable import MemoryLanes

final class LimitPointAnalyzerTests: XCTestCase {
    func testStoppingAndSightDistanceMatchDocumentedModel() {
        let analyzer = LimitPointAnalyzer()

        XCTAssertEqual(analyzer.sightDistance(radiusMeters: 38), 39.5, accuracy: 0.2)
        XCTAssertEqual(analyzer.stoppingDistance(speedKmh: 90, wet: false), 69.6, accuracy: 0.2)
        XCTAssertGreaterThan(
            analyzer.stoppingDistance(speedKmh: 90, wet: true),
            analyzer.stoppingDistance(speedKmh: 90, wet: false)
        )
    }

    func testQuarterCircleProducesAFlaggedBendAtReferenceSpeed() throws {
        let analysis = LimitPointAnalyzer().analyze(route: quarterCircle(radiusMeters: 50), referenceSpeedKmh: 90)

        let corner = try XCTUnwrap(analysis.corners.first)
        XCTAssertEqual(corner.radiusMeters, 50, accuracy: 8)
        XCTAssertGreaterThan(corner.sweepDegrees, 45)
        XCTAssertLessThan(corner.marginMeters, 0)
        XCTAssertEqual(analysis.beyondViewCount, 1)
    }

    func testStraightRouteDoesNotInventCorners() {
        let route = (0..<60).map { index in
            Coordinate(latitude: Double(index) * 5 / 111_320, longitude: 0)
        }

        let analysis = LimitPointAnalyzer().analyze(route: route, referenceSpeedKmh: 70)

        XCTAssertTrue(analysis.corners.isEmpty)
    }

    func testHigherSpeedNeverImprovesMargin() throws {
        let route = quarterCircle(radiusMeters: 50)
        let slower = try XCTUnwrap(
            LimitPointAnalyzer().analyze(route: route, referenceSpeedKmh: 50).corners.first
        )
        let faster = try XCTUnwrap(
            LimitPointAnalyzer().analyze(route: route, referenceSpeedKmh: 90).corners.first
        )

        XCTAssertLessThan(faster.marginMeters, slower.marginMeters)
    }

    func testLongerReactionTimeNeverImprovesMargin() throws {
        let route = quarterCircle(radiusMeters: 50)
        let oneSecond = try XCTUnwrap(
            LimitPointAnalyzer(reactionSeconds: 1).analyze(route: route, referenceSpeedKmh: 70).corners.first
        )
        let twoSeconds = try XCTUnwrap(
            LimitPointAnalyzer(reactionSeconds: 2).analyze(route: route, referenceSpeedKmh: 70).corners.first
        )

        XCTAssertLessThan(twoSeconds.marginMeters, oneSecond.marginMeters)
    }

    private func quarterCircle(radiusMeters: Double) -> [Coordinate] {
        stride(from: 0.0, through: 90.0, by: 3.0).map { degrees in
            let radians = degrees * .pi / 180
            let east = radiusMeters * cos(radians)
            let north = radiusMeters * sin(radians)
            return Coordinate(latitude: north / 111_320, longitude: east / 111_320)
        }
    }
}
