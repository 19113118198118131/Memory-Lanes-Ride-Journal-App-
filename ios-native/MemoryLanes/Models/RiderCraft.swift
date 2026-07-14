import Foundation

enum RiderCraftFeature {
    #if DEBUG
    static let isResearchPreviewEnabled = true
    #else
    static let isResearchPreviewEnabled = false
    #endif
}

struct RiderCraftEvent: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case brakeAfterTurnIn
        case flatExit
        case earlyApex
        case brakedDeep

        var title: String {
            switch self {
            case .brakeAfterTurnIn: "Braking after turn-in"
            case .flatExit: "Flat exit"
            case .earlyApex: "Early-apex pattern"
            case .brakedDeep: "Braked deep"
            }
        }

        static let calibrationControlKinds: [Self] = [
            .brakeAfterTurnIn,
            .flatExit,
            .brakedDeep
        ]
    }

    let kind: Kind
    let cornerIndex: Int
    let replayIndex: Int
    let measuredValue: Double
    let threshold: Double

    var id: String { "\(kind.rawValue)-\(cornerIndex)-\(replayIndex)" }
}

struct RiderCraftCalibrationSample: Hashable, Sendable {
    let cornerIndex: Int
    let replayIndex: Int
    let drive: Double
    let apexPosition: Double
    let brakeDepth: Double
    let brakeAfterTurnInProgress: Double?
}

struct RiderCraftCalibrationReviewTarget: Identifiable, Hashable, Sendable {
    let id: String
    let candidateKind: RiderCraftEvent.Kind?
    let cornerIndex: Int
    let replayIndex: Int
    let measuredValue: Double?
    let threshold: Double?

    var isControl: Bool { candidateKind == nil }
}

struct RiderCraftCalibrationReview: Identifiable, Codable, Equatable, Sendable {
    enum Decision: String, Codable, CaseIterable, Sendable {
        case match
        case mismatch
        case unsure
    }

    let rideID: UUID
    let thresholdVersion: Int
    let targetID: String
    let candidateKind: RiderCraftEvent.Kind?
    let cornerIndex: Int
    let replayIndex: Int
    let measuredValue: Double?
    let threshold: Double?
    let suspectedKind: RiderCraftEvent.Kind?
    let decision: Decision
    let reviewedAt: Date

    var id: String { "\(rideID.uuidString)-v\(thresholdVersion)-\(targetID)" }

    init(
        rideID: UUID,
        thresholdVersion: Int,
        targetID: String,
        candidateKind: RiderCraftEvent.Kind?,
        cornerIndex: Int,
        replayIndex: Int,
        measuredValue: Double?,
        threshold: Double?,
        suspectedKind: RiderCraftEvent.Kind? = nil,
        decision: Decision,
        reviewedAt: Date
    ) {
        self.rideID = rideID
        self.thresholdVersion = thresholdVersion
        self.targetID = targetID
        self.candidateKind = candidateKind
        self.cornerIndex = cornerIndex
        self.replayIndex = replayIndex
        self.measuredValue = measuredValue
        self.threshold = threshold
        self.suspectedKind = suspectedKind
        self.decision = decision
        self.reviewedAt = reviewedAt
    }
}

struct RiderCraftCalibrationReviewSummary: Codable, Equatable, Sendable {
    struct Detector: Codable, Equatable, Sendable {
        let kind: RiderCraftEvent.Kind
        var candidateMatches: Int
        var candidateMismatches: Int
        var candidateUnsure: Int
        var controlMisses: Int

        var candidateReviewed: Int {
            candidateMatches + candidateMismatches + candidateUnsure
        }
    }

    let reviewedCount: Int
    let candidateReviewed: Int
    let controlReviewed: Int
    let controlNoMisses: Int
    let controlMisses: Int
    let controlUnsure: Int
    let unclassifiedControlMisses: Int
    let detectors: [Detector]

    init(reviews: [RiderCraftCalibrationReview]) {
        var detectorMap = Dictionary(uniqueKeysWithValues: RiderCraftEvent.Kind.allCases.map {
            ($0, Detector(kind: $0, candidateMatches: 0, candidateMismatches: 0, candidateUnsure: 0, controlMisses: 0))
        })
        var candidateReviewed = 0
        var controlReviewed = 0
        var controlNoMisses = 0
        var controlMisses = 0
        var controlUnsure = 0
        var unclassifiedControlMisses = 0

        for review in reviews {
            if let kind = review.candidateKind {
                candidateReviewed += 1
                switch review.decision {
                case .match:
                    detectorMap[kind]?.candidateMatches += 1
                case .mismatch:
                    detectorMap[kind]?.candidateMismatches += 1
                case .unsure:
                    detectorMap[kind]?.candidateUnsure += 1
                }
            } else {
                controlReviewed += 1
                switch review.decision {
                case .match:
                    controlNoMisses += 1
                case .mismatch:
                    controlMisses += 1
                    if let kind = review.suspectedKind {
                        detectorMap[kind]?.controlMisses += 1
                    } else {
                        unclassifiedControlMisses += 1
                    }
                case .unsure:
                    controlUnsure += 1
                }
            }
        }

        reviewedCount = reviews.count
        self.candidateReviewed = candidateReviewed
        self.controlReviewed = controlReviewed
        self.controlNoMisses = controlNoMisses
        self.controlMisses = controlMisses
        self.controlUnsure = controlUnsure
        self.unclassifiedControlMisses = unclassifiedControlMisses
        detectors = RiderCraftEvent.Kind.allCases.compactMap { detectorMap[$0] }
    }
}

struct RiderCraftAnalysis: Sendable {
    let thresholdVersion: Int
    let detectedCornerCount: Int
    let events: [RiderCraftEvent]
    let calibrationSamples: [RiderCraftCalibrationSample]
    let eventsPerCorner: Double?
    let unavailableReason: String?

    static func unavailable(_ reason: String) -> RiderCraftAnalysis {
        RiderCraftAnalysis(
            thresholdVersion: RiderCraftThresholds.current.version,
            detectedCornerCount: 0,
            events: [],
            calibrationSamples: [],
            eventsPerCorner: nil,
            unavailableReason: reason
        )
    }

    var categoryCounts: [RiderCraftEvent.Kind: Int] {
        Dictionary(grouping: events, by: \.kind).mapValues(\.count)
    }

    var calibrationReviewTargets: [RiderCraftCalibrationReviewTarget] {
        let candidateTargets = events.map { event in
            RiderCraftCalibrationReviewTarget(
                id: event.id,
                candidateKind: event.kind,
                cornerIndex: event.cornerIndex,
                replayIndex: event.replayIndex,
                measuredValue: event.measuredValue,
                threshold: event.threshold
            )
        }
        let candidateCorners = Set(events.map(\.cornerIndex))
        let controls = calibrationSamples
            .filter { !candidateCorners.contains($0.cornerIndex) }
            .map { sample in
                RiderCraftCalibrationReviewTarget(
                    id: "control-\(sample.cornerIndex)-\(sample.replayIndex)",
                    candidateKind: nil,
                    cornerIndex: sample.cornerIndex,
                    replayIndex: sample.replayIndex,
                    measuredValue: nil,
                    threshold: nil
                )
            }
        return (candidateTargets + controls).sorted {
            if $0.replayIndex == $1.replayIndex { return $0.id < $1.id }
            return $0.replayIndex < $1.replayIndex
        }
    }

    var calibrationDebriefLine: String? {
        guard eventsPerCorner != nil,
              let dominant = RiderCraftEvent.Kind.allCases.max(by: {
                  categoryCounts[$0, default: 0] < categoryCounts[$1, default: 0]
              }),
              categoryCounts[dominant, default: 0] > 0 else { return nil }
        let count = categoryCounts[dominant, default: 0]
        switch dominant {
        case .brakeAfterTurnIn:
            return "\(count) detected corner\(count == 1 ? "" : "s") where braking began after turn-in. That is the one worth reviewing."
        case .flatExit:
            return "\(count) detected corner\(count == 1 ? "" : "s") with little clear drive on exit. Review the replay before treating it as a pattern."
        case .earlyApex:
            return "\(count) detected corner\(count == 1 ? "" : "s") showed an early-apex pattern. Road geometry can influence this proxy."
        case .brakedDeep:
            return "\(count) detected corner\(count == 1 ? "" : "s") where braking continued deep towards the apex. That is the one worth reviewing."
        }
    }
}

struct RiderCraftCalibrationDistribution: Codable, Equatable, Sendable {
    let count: Int
    let minimum: Double?
    let lowerQuartile: Double?
    let median: Double?
    let upperQuartile: Double?
    let maximum: Double?

    init(values: [Double]) {
        let sorted = values.filter(\.isFinite).sorted()
        count = sorted.count
        minimum = sorted.first
        lowerQuartile = Self.percentile(0.25, in: sorted)
        median = Self.percentile(0.5, in: sorted)
        upperQuartile = Self.percentile(0.75, in: sorted)
        maximum = sorted.last
    }

    private static func percentile(_ fraction: Double, in sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard lower != upper else { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }
}

struct RiderCraftThresholdSensitivity: Codable, Equatable, Sendable {
    let threshold: Double
    let eventCount: Int
    let ratePerCorner: Double
}

struct RiderCraftCalibrationReport: Codable, Equatable, Sendable {
    let thresholdVersion: Int
    let rideCount: Int
    let eligibleRideCount: Int
    let insufficientRideCount: Int
    let detectedCornerCount: Int
    let eventCount: Int
    let eventsPerCorner: Double?
    let categoryCounts: [String: Int]
    let categoryRatesPerCorner: [String: Double]
    let drive: RiderCraftCalibrationDistribution
    let apexPosition: RiderCraftCalibrationDistribution
    let brakeDepth: RiderCraftCalibrationDistribution
    let brakeAfterTurnInProgress: RiderCraftCalibrationDistribution
    let flatExitSensitivity: [RiderCraftThresholdSensitivity]
    let earlyApexSensitivity: [RiderCraftThresholdSensitivity]
    let deepBrakingSensitivity: [RiderCraftThresholdSensitivity]
    let brakeAfterTurnInSensitivity: [RiderCraftThresholdSensitivity]

    init(analyses: [RiderCraftAnalysis]) {
        let samples = analyses.flatMap(\.calibrationSamples)
        let events = analyses.flatMap(\.events)
        let corners = analyses.map(\.detectedCornerCount).reduce(0, +)
        let counts = Dictionary(uniqueKeysWithValues: RiderCraftEvent.Kind.allCases.map { kind in
            (kind.rawValue, events.filter { $0.kind == kind }.count)
        })

        thresholdVersion = analyses.map(\.thresholdVersion).max() ?? RiderCraftThresholds.current.version
        rideCount = analyses.count
        eligibleRideCount = analyses.filter { $0.eventsPerCorner != nil }.count
        insufficientRideCount = analyses.count - eligibleRideCount
        detectedCornerCount = corners
        eventCount = events.count
        eventsPerCorner = corners > 0 ? Double(events.count) / Double(corners) : nil
        categoryCounts = counts
        categoryRatesPerCorner = counts.mapValues { count in
            corners > 0 ? Double(count) / Double(corners) : 0
        }
        drive = RiderCraftCalibrationDistribution(values: samples.map(\.drive))
        apexPosition = RiderCraftCalibrationDistribution(values: samples.map(\.apexPosition))
        brakeDepth = RiderCraftCalibrationDistribution(values: samples.map(\.brakeDepth))
        brakeAfterTurnInProgress = RiderCraftCalibrationDistribution(
            values: samples.compactMap(\.brakeAfterTurnInProgress)
        )
        flatExitSensitivity = Self.sensitivity(
            thresholds: [-0.10, 0, 0.05, 0.10, 0.15],
            cornerCount: corners,
            values: samples.map(\.drive),
            matches: <
        )
        earlyApexSensitivity = Self.sensitivity(
            thresholds: [0.10, 0.15, 0.20, 0.25, 0.30, 0.35],
            cornerCount: corners,
            values: samples.map(\.apexPosition),
            matches: <=
        )
        deepBrakingSensitivity = Self.sensitivity(
            thresholds: [0.40, 0.50, 0.60, 0.70, 0.80],
            cornerCount: corners,
            values: samples.map(\.brakeDepth),
            matches: >
        )
        brakeAfterTurnInSensitivity = Self.sensitivity(
            thresholds: [0, 0.10, 0.20, 0.30, 0.50],
            cornerCount: corners,
            values: samples.compactMap(\.brakeAfterTurnInProgress),
            matches: >
        )
    }

    private static func sensitivity(
        thresholds: [Double],
        cornerCount: Int,
        values: [Double],
        matches: (Double, Double) -> Bool
    ) -> [RiderCraftThresholdSensitivity] {
        thresholds.map { threshold in
            let count = values.filter { matches($0, threshold) }.count
            return RiderCraftThresholdSensitivity(
                threshold: threshold,
                eventCount: count,
                ratePerCorner: cornerCount > 0 ? Double(count) / Double(cornerCount) : 0
            )
        }
    }
}

struct RiderCraftThresholds: Sendable {
    let version: Int
    let flatExitDrive: Double
    let earlyApexPosition: Double
    let deepBrakingDepth: Double

    static let current = RiderCraftThresholds(
        version: 1,
        flatExitDrive: 0.10,
        earlyApexPosition: 0.35,
        deepBrakingDepth: 0.60
    )
}

struct RiderCraftFocus: Sendable {
    let kind: RideCoachScore.Kind
    let title: String
    let evidence: String
    let drill: String
    let target: String
}

struct RiderCraftTrendPoint: Identifiable, Sendable {
    let rideID: UUID
    let date: Date
    let rate: Double

    var id: UUID { rideID }
}

struct RiderCraftBadge: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case settledEntry
        case smoothHands
        case repeatable
        case lateApexHabit
        case wetDiscipline
    }

    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
    let isEarned: Bool

    var id: Kind { kind }
}

struct RiderCraftProgress: Sendable {
    let eligibleRideCount: Int
    let currentRate: Double?
    let comparisonRate: Double?
    let trend: [RiderCraftTrendPoint]
    let focus: RiderCraftFocus?
    let badges: [RiderCraftBadge]
    let totalCorners: Int
    let totalEvents: Int

    var rateDelta: Double? {
        guard let currentRate, let comparisonRate else { return nil }
        return currentRate - comparisonRate
    }
}
