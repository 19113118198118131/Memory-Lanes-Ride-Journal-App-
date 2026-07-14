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
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.reviews, reviews)
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
        decision: RiderCraftCalibrationReview.Decision
    ) -> RiderCraftCalibrationReview {
        RiderCraftCalibrationReview(
            rideID: rideID,
            thresholdVersion: 1,
            targetID: "flatExit-1-15",
            candidateKind: .flatExit,
            cornerIndex: 1,
            replayIndex: 15,
            measuredValue: 0.05,
            threshold: 0.10,
            decision: decision,
            reviewedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private struct TestArchive: Decodable {
    let version: Int
    let reviews: [RiderCraftCalibrationReview]
}

private extension JSONDecoder {
    static var reviewArchive: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
