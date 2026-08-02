import XCTest
@testable import MemoryLanes

final class LimitPointCalibrationReviewTests: XCTestCase {
    func testReviewStorePersistsUpdatesAndScopesByRideAndModel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("limit-point-review-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("reviews.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let rideID = UUID()
        let otherRideID = UUID()
        let store = LimitPointCalibrationReviewStore(fileURL: fileURL)
        try await store.save(review(rideID: rideID, cornerID: 1, decision: .unsure))
        try await store.save(review(rideID: rideID, cornerID: 1, decision: .match))
        try await store.save(review(rideID: otherRideID, cornerID: 1, decision: .mismatch))

        let reloaded = LimitPointCalibrationReviewStore(fileURL: fileURL)
        let rideReviews = try await reloaded.reviews(for: rideID, modelVersion: 1)
        let allReviews = try await reloaded.allReviews(modelVersion: 1)

        XCTAssertEqual(rideReviews.count, 1)
        XCTAssertEqual(rideReviews.first?.decision, .match)
        XCTAssertEqual(allReviews.count, 2)
    }

    func testReviewCanBeClearedWithoutRemovingOtherCorners() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("limit-point-clear-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("reviews.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let rideID = UUID()
        let store = LimitPointCalibrationReviewStore(fileURL: fileURL)
        try await store.save(review(rideID: rideID, cornerID: 1, decision: .match))
        try await store.save(review(rideID: rideID, cornerID: 2, decision: .unsure))

        try await store.removeReview(for: rideID, modelVersion: 1, cornerID: 1)
        let reviews = try await store.reviews(for: rideID, modelVersion: 1)

        XCTAssertEqual(reviews.map(\.cornerID), [2])
    }

    private func review(
        rideID: UUID,
        cornerID: Int,
        decision: LimitPointCalibrationReview.Decision
    ) -> LimitPointCalibrationReview {
        LimitPointCalibrationReview(
            rideID: rideID,
            modelVersion: 1,
            cornerID: cornerID,
            replayIndex: cornerID * 10,
            severity: .beyondView,
            decision: decision,
            reviewedAt: Date()
        )
    }
}
