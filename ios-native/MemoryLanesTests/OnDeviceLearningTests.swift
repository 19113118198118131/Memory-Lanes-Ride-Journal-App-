import XCTest
@testable import MemoryLanes

final class OnDeviceLearningTests: XCTestCase {
    func testBayesianReliabilityNeedsEvidenceBeforePersonalising() {
        let sparse = BayesianReliability(matches: 2, mismatches: 0)
        let trained = BayesianReliability(matches: 7, mismatches: 1)

        XCTAssertEqual(sparse.stage, .learning)
        XCTAssertEqual(trained.stage, .personalised)
        XCTAssertGreaterThan(trained.estimatedAgreement, sparse.estimatedAgreement)
        XCTAssertLessThan(trained.estimatedAgreement, 1)
    }

    func testRiderCraftLearningSeparatesDetectorFeedback() {
        let rideID = UUID()
        let reviews = [
            craftReview(rideID: rideID, target: "flat-1", kind: .flatExit, decision: .match),
            craftReview(rideID: rideID, target: "flat-2", kind: .flatExit, decision: .mismatch),
            craftReview(rideID: rideID, target: "deep-1", kind: .brakedDeep, decision: .match)
        ]

        let model = RiderCraftPersonalization(reviews: reviews)

        XCTAssertEqual(model.reliability(for: .flatExit).reviewedCount, 2)
        XCTAssertEqual(model.reliability(for: .brakedDeep).reviewedCount, 1)
        XCTAssertEqual(model.reliability(for: .brakeAfterTurnIn).reviewedCount, 0)
    }

    func testLimitPointLearningNeverChangesRawSeverity() {
        let review = LimitPointCalibrationReview(
            rideID: UUID(),
            modelVersion: 1,
            cornerID: 2,
            replayIndex: 40,
            severity: .severe,
            decision: .mismatch,
            reviewedAt: Date()
        )

        let model = LimitPointPersonalization(reviews: [review])

        XCTAssertEqual(model.reliability(for: .severe).reviewedCount, 1)
        XCTAssertEqual(review.severity, .severe)
    }

    private func craftReview(
        rideID: UUID,
        target: String,
        kind: RiderCraftEvent.Kind,
        decision: RiderCraftCalibrationReview.Decision
    ) -> RiderCraftCalibrationReview {
        RiderCraftCalibrationReview(
            rideID: rideID,
            thresholdVersion: RiderCraftThresholds.current.version,
            targetID: target,
            candidateKind: kind,
            cornerIndex: 1,
            replayIndex: 10,
            measuredValue: 0,
            threshold: 0,
            decision: decision,
            reviewedAt: Date()
        )
    }
}
