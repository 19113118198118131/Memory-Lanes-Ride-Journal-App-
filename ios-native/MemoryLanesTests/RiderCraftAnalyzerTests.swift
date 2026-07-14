import XCTest
@testable import MemoryLanes

final class RiderCraftAnalyzerTests: XCTestCase {
    func testDetectsEachSupportedSurvivalReactionWithReplayEvidence() throws {
        let corners = [
            signal(index: 1, start: 10, apex: 15, end: 20, drive: 0.05, apexPosition: 0.25, brakeDepth: 0.75),
            signal(index: 2, start: 30, apex: 35, end: 40, drive: 0.50, apexPosition: 0.55, brakeDepth: 0.20),
            signal(index: 3, start: 50, apex: 55, end: 60, drive: 0.50, apexPosition: 0.55, brakeDepth: 0.20)
        ]
        let braking = [zone(start: 12, end: 14)]

        let analysis = RiderCraftAnalyzer().analyze(corners: corners, brakingZones: braking)

        XCTAssertEqual(try XCTUnwrap(analysis.eventsPerCorner), 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(analysis.categoryCounts[.brakeAfterTurnIn], 1)
        XCTAssertEqual(analysis.categoryCounts[.flatExit], 1)
        XCTAssertEqual(analysis.categoryCounts[.earlyApex], 1)
        XCTAssertEqual(analysis.categoryCounts[.brakedDeep], 1)
        XCTAssertEqual(try XCTUnwrap(analysis.events.first(where: { $0.kind == .brakeAfterTurnIn })).replayIndex, 12)
        XCTAssertTrue(analysis.events.allSatisfy { $0.cornerIndex > 0 && $0.replayIndex > 0 })
    }

    func testSettledSignalsDoNotCreateFalseEvents() {
        let corners = [
            signal(index: 1, start: 10, apex: 15, end: 20, drive: 0.35, apexPosition: 0.50, brakeDepth: 0.30),
            signal(index: 2, start: 30, apex: 35, end: 40, drive: 0.45, apexPosition: 0.60, brakeDepth: 0.15),
            signal(index: 3, start: 50, apex: 55, end: 60, drive: 0.25, apexPosition: 0.45, brakeDepth: 0.40)
        ]
        let brakingBeforeTurnIn = [zone(start: 5, end: 9)]

        let analysis = RiderCraftAnalyzer().analyze(corners: corners, brakingZones: brakingBeforeTurnIn)

        XCTAssertEqual(analysis.eventsPerCorner, 0)
        XCTAssertTrue(analysis.events.isEmpty)
        XCTAssertNil(analysis.calibrationDebriefLine)
    }

    func testInsufficientCornersRetainCalibrationEvidenceWithoutPublishingRate() {
        let analysis = RiderCraftAnalyzer().analyze(
            corners: [signal(index: 1, start: 10, apex: 15, end: 20, drive: 0, apexPosition: 0.2, brakeDepth: 0.8)],
            brakingZones: []
        )

        XCTAssertNil(analysis.eventsPerCorner)
        XCTAssertNotNil(analysis.unavailableReason)
        XCTAssertEqual(analysis.events.count, 3)
        XCTAssertNil(analysis.calibrationDebriefLine)
    }

    func testCalibrationDebriefNamesOnlyDominantSupportedSignal() throws {
        let corners = (1...3).map { index in
            signal(index: index, start: index * 20, apex: index * 20 + 5, end: index * 20 + 10, drive: 0, apexPosition: 0.5, brakeDepth: 0.2)
        }

        let analysis = RiderCraftAnalyzer().analyze(corners: corners, brakingZones: [])
        let line = try XCTUnwrap(analysis.calibrationDebriefLine)

        XCTAssertTrue(line.contains("3 detected corners"))
        XCTAssertTrue(line.contains("drive on exit"))
        XCTAssertFalse(line.contains("score"))
    }

    private func signal(
        index: Int,
        start: Int,
        apex: Int,
        end: Int,
        drive: Double,
        apexPosition: Double,
        brakeDepth: Double
    ) -> RiderCraftCornerSignal {
        RiderCraftCornerSignal(
            cornerIndex: index,
            startIndex: start,
            apexIndex: apex,
            endIndex: end,
            drive: drive,
            apexPosition: apexPosition,
            brakeDepth: brakeDepth
        )
    }

    private func zone(start: Int, end: Int) -> RideInputZone {
        RideInputZone(
            kind: .braking,
            startIndex: start,
            endIndex: end,
            startKm: 0,
            endKm: 0,
            peakAcceleration: -2,
            smoothness: 80
        )
    }
}
