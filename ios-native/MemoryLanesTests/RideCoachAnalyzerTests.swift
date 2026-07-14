import CoreLocation
import XCTest
@testable import MemoryLanes

final class RideCoachAnalyzerTests: XCTestCase {
    func testShortTrackReturnsHonestUnavailableAnalysis() {
        let points = makeStraightTrack(speeds: Array(repeating: 10, count: 10))

        let analysis = RideCoachAnalyzer().analyze(points: points)

        XCTAssertNil(analysis.score)
        XCTAssertTrue(analysis.analytics.acceleration.isEmpty)
        XCTAssertTrue(analysis.corners.isEmpty)
    }

    func testInputZonesAndCompositionComeFromSamePointStream() {
        let speeds =
            Array(repeating: 9.0, count: 8) +
            [9, 12, 15, 18, 21, 23] +
            Array(repeating: 23.0, count: 8) +
            [23, 20, 17, 14, 11, 8] +
            Array(repeating: 10.0, count: 8) +
            [10, 13, 16, 19, 22, 24] +
            Array(repeating: 24.0, count: 8) +
            [24, 21, 18, 15, 12, 9]
        let points = makeStraightTrack(speeds: speeds)

        let analysis = RideCoachAnalyzer().analyze(points: points)

        XCTAssertFalse(analysis.analytics.acceleration.isEmpty)
        XCTAssertGreaterThanOrEqual(analysis.analytics.driveZones.count, 2)
        XCTAssertGreaterThanOrEqual(analysis.analytics.brakingZones.count, 2)
        XCTAssertEqual(analysis.analytics.composition.count, RideCompositionSlice.Kind.allCases.count)
        XCTAssertGreaterThan(analysis.analytics.composition.map(\.seconds).reduce(0, +), 30)
        XCTAssertNotNil(analysis.scores.first(where: { $0.kind == .brakingFeel }))
        XCTAssertNotNil(analysis.scores.first(where: { $0.kind == .throttleFeel }))
    }

    func testKnownRadiusBendProducesCornerGeometryAndGripEvidence() throws {
        let points = makeCornerTrack()

        let analysis = RideCoachAnalyzer().analyze(points: points)
        let corner = try XCTUnwrap(analysis.corners.first)
        let chartPoint = try XCTUnwrap(analysis.analytics.cornerPoints.first)
        let replayIndex = try XCTUnwrap(corner.replayIndex)

        XCTAssertEqual(Double(corner.radiusMeters ?? 0), 80, accuracy: 12)
        XCTAssertGreaterThan(corner.sweepDegrees ?? 0, 80)
        XCTAssertGreaterThan(corner.lateralG ?? 0, 0.15)
        XCTAssertEqual(replayIndex, chartPoint.replayIndex)
        XCTAssertFalse(analysis.analytics.gripUsage.isEmpty)
    }

    func testStorageSummaryIncludesCompositionAndLeanFingerprint() throws {
        let analysis = RideCoachAnalyzer().analyze(points: makeCornerTrack())
        let summary = try XCTUnwrap(analysis.storageSummary)
        let data = try JSONEncoder().encode(summary)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let composition = try XCTUnwrap(object["comp"] as? [String: Any])
        let corners = try XCTUnwrap(object["corners"] as? [[String: Any]])

        XCTAssertFalse(composition.isEmpty)
        XCTAssertNotNil(corners.first?["ld"])
    }

    private func makeStraightTrack(speeds: [Double]) -> [RecordingPoint] {
        var x = 0.0
        return speeds.enumerated().map { index, speed in
            if index > 0 { x += speed }
            return point(x: x, y: 0, time: TimeInterval(index))
        }
    }

    private func makeCornerTrack() -> [RecordingPoint] {
        let speed = 15.0
        let radius = 80.0
        var positions: [(Double, Double)] = (0..<10).map { (Double($0) * speed, 0) }
        let centreX = positions.last?.0 ?? 0
        let centreY = radius
        let angleStep = speed / radius

        for step in 1...13 {
            let angle = -.pi / 2 + Double(step) * angleStep
            positions.append((centreX + radius * cos(angle), centreY + radius * sin(angle)))
        }

        let endAngle = -.pi / 2 + 13 * angleStep
        let tangent = endAngle + .pi / 2
        let arcEnd = positions.last ?? (centreX, centreY - radius)
        for step in 1...20 {
            positions.append((
                arcEnd.0 + Double(step) * speed * cos(tangent),
                arcEnd.1 + Double(step) * speed * sin(tangent)
            ))
        }

        return positions.enumerated().map { index, position in
            point(x: position.0, y: position.1, time: TimeInterval(index))
        }
    }

    private func point(x: Double, y: Double, time: TimeInterval) -> RecordingPoint {
        let latitude = -36.85 + y / 110_540
        let longitude = 174.76 + x / (111_320 * cos(latitude * .pi / 180))
        return RecordingPoint(location: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 100,
            horizontalAccuracy: 3,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + time)
        ))
    }
}
