import Foundation

struct RiderCraftCornerSignal: Sendable {
    let cornerIndex: Int
    let startIndex: Int
    let apexIndex: Int
    let endIndex: Int
    let drive: Double
    let apexPosition: Double
    let brakeDepth: Double
}

struct RiderCraftAnalyzer: Sendable {
    let thresholds: RiderCraftThresholds
    let minimumCornerCount: Int

    init(thresholds: RiderCraftThresholds = .current, minimumCornerCount: Int = 3) {
        self.thresholds = thresholds
        self.minimumCornerCount = minimumCornerCount
    }

    func analyze(corners: [RiderCraftCornerSignal], brakingZones: [RideInputZone]) -> RiderCraftAnalysis {
        guard !corners.isEmpty else { return .unavailable("No significant corners detected") }
        var events: [RiderCraftEvent] = []

        for corner in corners {
            if let zone = brakingZones.first(where: {
                $0.startIndex > corner.startIndex && $0.startIndex <= corner.endIndex
            }) {
                let progress = Double(zone.startIndex - corner.startIndex) / Double(max(1, corner.endIndex - corner.startIndex))
                events.append(event(.brakeAfterTurnIn, corner: corner, replayIndex: zone.startIndex, value: progress, threshold: 0))
            }
            if corner.drive < thresholds.flatExitDrive {
                events.append(event(.flatExit, corner: corner, replayIndex: corner.apexIndex, value: corner.drive, threshold: thresholds.flatExitDrive))
            }
            if corner.apexPosition <= thresholds.earlyApexPosition {
                events.append(event(.earlyApex, corner: corner, replayIndex: corner.apexIndex, value: corner.apexPosition, threshold: thresholds.earlyApexPosition))
            }
            if corner.brakeDepth > thresholds.deepBrakingDepth {
                events.append(event(.brakedDeep, corner: corner, replayIndex: corner.apexIndex, value: corner.brakeDepth, threshold: thresholds.deepBrakingDepth))
            }
        }

        let isSufficient = corners.count >= minimumCornerCount
        return RiderCraftAnalysis(
            thresholdVersion: thresholds.version,
            detectedCornerCount: corners.count,
            events: events,
            eventsPerCorner: isSufficient ? Double(events.count) / Double(corners.count) : nil,
            unavailableReason: isSufficient ? nil : "At least \(minimumCornerCount) detected corners are needed"
        )
    }

    private func event(
        _ kind: RiderCraftEvent.Kind,
        corner: RiderCraftCornerSignal,
        replayIndex: Int,
        value: Double,
        threshold: Double
    ) -> RiderCraftEvent {
        RiderCraftEvent(
            kind: kind,
            cornerIndex: corner.cornerIndex,
            replayIndex: replayIndex,
            measuredValue: value,
            threshold: threshold
        )
    }
}

struct RiderCraftStorageSummary: Encodable, Sendable {
    struct StoredEvent: Encodable, Sendable {
        let kind: String
        let cornerIndex: Int
        let replayIndex: Int
        let measuredValue: Double
        let threshold: Double
    }

    let version: Int
    let calibrated: Bool
    let cornerCount: Int
    let eventCount: Int
    let eventsPerCorner: Double?
    let counts: [String: Int]
    let events: [StoredEvent]
    let unavailableReason: String?

    init(analysis: RiderCraftAnalysis) {
        version = analysis.thresholdVersion
        calibrated = false
        cornerCount = analysis.detectedCornerCount
        eventCount = analysis.events.count
        eventsPerCorner = analysis.eventsPerCorner
        counts = Dictionary(uniqueKeysWithValues: RiderCraftEvent.Kind.allCases.map {
            ($0.rawValue, analysis.categoryCounts[$0, default: 0])
        })
        events = analysis.events.prefix(120).map {
            StoredEvent(
                kind: $0.kind.rawValue,
                cornerIndex: $0.cornerIndex,
                replayIndex: $0.replayIndex,
                measuredValue: $0.measuredValue,
                threshold: $0.threshold
            )
        }
        unavailableReason = analysis.unavailableReason
    }
}
