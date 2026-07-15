import XCTest
@testable import MemoryLanes

final class RiderCraftCalibrationReviewTests: XCTestCase {
    func testReviewTargetsIncludeCandidatesAndUnflaggedControls() throws {
        let thresholds = RiderCraftThresholds(
            version: 7,
            flatExitDrive: 0.10,
            earlyApexPosition: -1,
            deepBrakingDepth: 2
        )
        let analysis = RiderCraftAnalyzer(thresholds: thresholds).analyze(
            corners: [
                signal(index: 1, start: 10, apex: 15, end: 20, drive: 0.05),
                signal(index: 2, start: 30, apex: 35, end: 40, drive: 0.30),
                signal(index: 3, start: 50, apex: 55, end: 60, drive: 0.40)
            ],
            brakingZones: []
        )

        let targets = analysis.calibrationReviewTargets

        XCTAssertEqual(targets.count, 3)
        XCTAssertEqual(targets.map(\.replayIndex), [15, 35, 55])
        XCTAssertEqual(targets.first?.candidateKind, .flatExit)
        XCTAssertEqual(targets.filter(\.isControl).count, 2)
        XCTAssertEqual(targets.last?.id, "control-3-55")
    }

    func testReviewStorePersistsUpdatesAndExportsVersionedArchive() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rider-craft-review-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("reviews.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let rideID = UUID()
        let original = review(rideID: rideID, decision: .unsure)
        let store = RiderCraftCalibrationReviewStore(fileURL: fileURL)
        try await store.save(original)
        try await store.save(review(rideID: rideID, decision: .mismatch))

        let reloaded = RiderCraftCalibrationReviewStore(fileURL: fileURL)
        let reviews = try await reloaded.reviews(for: rideID, thresholdVersion: 1)
        let exportURL = try await reloaded.makeExportFile()
        defer { try? FileManager.default.removeItem(at: exportURL) }
        let archive = try JSONDecoder.reviewArchive.decode(TestArchive.self, from: Data(contentsOf: exportURL))

        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews.first?.decision, .mismatch)
        XCTAssertEqual(archive.version, 2)
        XCTAssertEqual(archive.reviews, reviews)
        XCTAssertEqual(archive.summary.candidateReviewed, 1)
        XCTAssertEqual(archive.summary.detectors.first(where: { $0.kind == .flatExit })?.candidateMismatches, 1)
    }

    func testReviewStoreCanUncheckOneTargetAndResetOnlyOneRide() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rider-craft-reset-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("reviews.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let rideID = UUID()
        let otherRideID = UUID()
        let store = RiderCraftCalibrationReviewStore(fileURL: fileURL)
        try await store.save(review(rideID: rideID, targetID: "first", decision: .match))
        try await store.save(review(rideID: rideID, targetID: "second", decision: .unsure))
        try await store.save(review(rideID: otherRideID, targetID: "other", decision: .mismatch))

        try await store.removeReview(for: rideID, thresholdVersion: 1, targetID: "first")
        var rideReviews = try await store.reviews(for: rideID, thresholdVersion: 1)
        XCTAssertEqual(rideReviews.map(\.targetID), ["second"])

        try await store.resetReviews(for: rideID, thresholdVersion: 1)
        rideReviews = try await store.reviews(for: rideID, thresholdVersion: 1)
        let otherRideReviews = try await store.reviews(for: otherRideID, thresholdVersion: 1)

        XCTAssertTrue(rideReviews.isEmpty)
        XCTAssertEqual(otherRideReviews.map(\.targetID), ["other"])
    }

    func testReviewSummaryAttributesControlMissToSelectedDetector() {
        let rideID = UUID()
        let reviews = [
            review(rideID: rideID, targetID: "flat-1", candidateKind: .flatExit, decision: .match),
            review(rideID: rideID, targetID: "deep-2", candidateKind: .brakedDeep, decision: .mismatch),
            review(
                rideID: rideID,
                targetID: "control-3",
                candidateKind: nil,
                suspectedKind: .brakeAfterTurnIn,
                decision: .mismatch
            ),
            review(rideID: rideID, targetID: "control-4", candidateKind: nil, decision: .match)
        ]

        let summary = RiderCraftCalibrationReviewSummary(reviews: reviews)

        XCTAssertEqual(summary.reviewedCount, 4)
        XCTAssertEqual(summary.candidateReviewed, 2)
        XCTAssertEqual(summary.controlReviewed, 2)
        XCTAssertEqual(summary.controlMisses, 1)
        XCTAssertEqual(summary.controlNoMisses, 1)
        XCTAssertEqual(summary.unclassifiedControlMisses, 0)
        XCTAssertEqual(summary.detectors.first(where: { $0.kind == .flatExit })?.candidateMatches, 1)
        XCTAssertEqual(summary.detectors.first(where: { $0.kind == .brakedDeep })?.candidateMismatches, 1)
        XCTAssertEqual(summary.detectors.first(where: { $0.kind == .brakeAfterTurnIn })?.controlMisses, 1)
    }

    func testVersionOneReviewWithoutSuspectedKindStillDecodes() throws {
        let rideID = UUID()
        let json = """
        {
          "rideID": "\(rideID.uuidString)",
          "thresholdVersion": 1,
          "targetID": "flatExit-1-15",
          "candidateKind": "flatExit",
          "cornerIndex": 1,
          "replayIndex": 15,
          "measuredValue": 0.05,
          "threshold": 0.10,
          "decision": "match",
          "reviewedAt": "2023-11-14T22:13:20Z"
        }
        """

        let decoded = try JSONDecoder.reviewArchive.decode(
            RiderCraftCalibrationReview.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(decoded.rideID, rideID)
        XCTAssertNil(decoded.suspectedKind)
    }

    private func signal(index: Int, start: Int, apex: Int, end: Int, drive: Double) -> RiderCraftCornerSignal {
        RiderCraftCornerSignal(
            cornerIndex: index,
            startIndex: start,
            apexIndex: apex,
            endIndex: end,
            drive: drive,
            apexPosition: 0.5,
            brakeDepth: 0.2
        )
    }

    private func review(
        rideID: UUID,
        targetID: String = "flatExit-1-15",
        candidateKind: RiderCraftEvent.Kind? = .flatExit,
        suspectedKind: RiderCraftEvent.Kind? = nil,
        decision: RiderCraftCalibrationReview.Decision
    ) -> RiderCraftCalibrationReview {
        RiderCraftCalibrationReview(
            rideID: rideID,
            thresholdVersion: 1,
            targetID: targetID,
            candidateKind: candidateKind,
            cornerIndex: 1,
            replayIndex: 15,
            measuredValue: 0.05,
            threshold: 0.10,
            suspectedKind: suspectedKind,
            decision: decision,
            reviewedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private struct TestArchive: Decodable {
    let version: Int
    let summary: RiderCraftCalibrationReviewSummary
    let reviews: [RiderCraftCalibrationReview]
}

private extension JSONDecoder {
    static var reviewArchive: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
