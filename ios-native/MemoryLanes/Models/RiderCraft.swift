import Foundation

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
    }

    let kind: Kind
    let cornerIndex: Int
    let replayIndex: Int
    let measuredValue: Double
    let threshold: Double

    var id: String { "\(kind.rawValue)-\(cornerIndex)-\(replayIndex)" }
}

struct RiderCraftAnalysis: Sendable {
    let thresholdVersion: Int
    let detectedCornerCount: Int
    let events: [RiderCraftEvent]
    let eventsPerCorner: Double?
    let unavailableReason: String?

    static func unavailable(_ reason: String) -> RiderCraftAnalysis {
        RiderCraftAnalysis(
            thresholdVersion: RiderCraftThresholds.current.version,
            detectedCornerCount: 0,
            events: [],
            eventsPerCorner: nil,
            unavailableReason: reason
        )
    }

    var categoryCounts: [RiderCraftEvent.Kind: Int] {
        Dictionary(grouping: events, by: \.kind).mapValues(\.count)
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
