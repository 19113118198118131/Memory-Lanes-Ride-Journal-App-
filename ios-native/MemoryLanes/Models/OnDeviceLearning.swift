import Foundation

/// A small, explainable online learner for human-reviewed model output.
/// The prior prevents a handful of taps from creating false certainty.
struct BayesianReliability: Codable, Equatable, Sendable {
    enum Stage: String, Codable, Sendable {
        case learning
        case personalised
    }

    let matches: Int
    let mismatches: Int
    let priorMatches: Double
    let priorMismatches: Double

    init(
        matches: Int,
        mismatches: Int,
        priorMatches: Double = 2,
        priorMismatches: Double = 2
    ) {
        self.matches = max(matches, 0)
        self.mismatches = max(mismatches, 0)
        self.priorMatches = max(priorMatches, 0)
        self.priorMismatches = max(priorMismatches, 0)
    }

    var reviewedCount: Int { matches + mismatches }

    var estimatedAgreement: Double {
        let numerator = priorMatches + Double(matches)
        let denominator = priorMatches + priorMismatches + Double(reviewedCount)
        return denominator > 0 ? numerator / denominator : 0.5
    }

    var stage: Stage { reviewedCount >= 6 ? .personalised : .learning }

    var statusText: String {
        switch stage {
        case .learning:
            return "Learning from \(reviewedCount) review\(reviewedCount == 1 ? "" : "s")"
        case .personalised:
            return "\(Int((estimatedAgreement * 100).rounded()))% matched your reviews"
        }
    }
}

struct RiderCraftPersonalization: Sendable {
    let reliabilityByKind: [RiderCraftEvent.Kind: BayesianReliability]

    static let empty = RiderCraftPersonalization(reliabilityByKind: [:])

    init(reviews: [RiderCraftCalibrationReview]) {
        reliabilityByKind = Dictionary(uniqueKeysWithValues: RiderCraftEvent.Kind.currentModelKinds.map { kind in
            let candidates = reviews.filter { $0.candidateKind == kind }
            let matches = candidates.filter { $0.decision == .match }.count
            let mismatches = candidates.filter { $0.decision == .mismatch }.count
                + reviews.filter {
                    $0.candidateKind == nil
                        && $0.suspectedKind == kind
                        && $0.decision == .mismatch
                }.count
            return (kind, BayesianReliability(matches: matches, mismatches: mismatches))
        })
    }

    private init(reliabilityByKind: [RiderCraftEvent.Kind: BayesianReliability]) {
        self.reliabilityByKind = reliabilityByKind
    }

    func reliability(for kind: RiderCraftEvent.Kind) -> BayesianReliability {
        reliabilityByKind[kind] ?? BayesianReliability(matches: 0, mismatches: 0)
    }
}

struct LimitPointPersonalization: Sendable {
    let reliabilityBySeverity: [LimitPointCorner.Severity: BayesianReliability]

    static let empty = LimitPointPersonalization(reliabilityBySeverity: [:])

    init(reviews: [LimitPointCalibrationReview]) {
        reliabilityBySeverity = Dictionary(uniqueKeysWithValues: LimitPointCorner.Severity.allCases.map { severity in
            let matchingSeverity = reviews.filter { $0.severity == severity }
            return (
                severity,
                BayesianReliability(
                    matches: matchingSeverity.filter { $0.decision == .match }.count,
                    mismatches: matchingSeverity.filter { $0.decision == .mismatch }.count
                )
            )
        })
    }

    private init(reliabilityBySeverity: [LimitPointCorner.Severity: BayesianReliability]) {
        self.reliabilityBySeverity = reliabilityBySeverity
    }

    func reliability(for severity: LimitPointCorner.Severity) -> BayesianReliability {
        reliabilityBySeverity[severity] ?? BayesianReliability(matches: 0, mismatches: 0)
    }
}
