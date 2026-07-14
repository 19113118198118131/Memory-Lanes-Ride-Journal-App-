import Foundation

struct RiderCraftProgressAnalyzer: Sendable {
    func analyze(rides: [Ride]) -> RiderCraftProgress {
        let eligible = rides
            .filter { $0.riderCraftSummary?.eventsPerCorner != nil }
            .sorted { $0.date > $1.date }
        let recent = Array(eligible.prefix(5))
        let current = eligible.first?.riderCraftSummary?.eventsPerCorner
        let comparisonValues = eligible.dropFirst().prefix(5).compactMap { $0.riderCraftSummary?.eventsPerCorner }
        let comparison = comparisonValues.isEmpty ? nil : comparisonValues.reduce(0, +) / Double(comparisonValues.count)
        let chronological = eligible.prefix(8).reversed().compactMap { ride -> RiderCraftTrendPoint? in
            guard let rate = ride.riderCraftSummary?.eventsPerCorner else { return nil }
            return RiderCraftTrendPoint(rideID: ride.id, date: ride.date, rate: rate)
        }
        let totalCorners = recent.compactMap { $0.riderCraftSummary?.cornerCount }.reduce(0, +)
        let totalEvents = recent.compactMap { $0.riderCraftSummary?.eventCount }.reduce(0, +)

        return RiderCraftProgress(
            eligibleRideCount: eligible.count,
            currentRate: current,
            comparisonRate: comparison,
            trend: chronological,
            focus: focus(from: recent),
            badges: badges(from: eligible.first),
            totalCorners: totalCorners,
            totalEvents: totalEvents
        )
    }

    private func focus(from rides: [Ride]) -> RiderCraftFocus? {
        var values: [RideCoachScore.Kind: [Double]] = [:]
        for ride in rides {
            for kind in RideCoachScore.Kind.allCases {
                if let value = ride.coachScores[kind.storageKey], value.isFinite {
                    values[kind, default: []].append(value)
                }
            }
        }
        guard let weakest = values.compactMap({ kind, scores -> (RideCoachScore.Kind, Double)? in
            guard !scores.isEmpty else { return nil }
            return (kind, scores.reduce(0, +) / Double(scores.count))
        }).min(by: { $0.1 < $1.1 }) else { return nil }

        let score = Int(weakest.1.rounded())
        switch weakest.0 {
        case .cornerEntry:
            return RiderCraftFocus(
                kind: weakest.0,
                title: "Settled Entry",
                evidence: "Corner entry averaged \(score) across your recent rides.",
                drill: "Choose a comfortable approach and finish braking before turn-in. Let the bike settle before asking it to steer.",
                target: "Fewer detected corners with braking after turn-in"
            )
        case .exitDrive:
            return RiderCraftFocus(
                kind: weakest.0,
                title: "Progressive Exit",
                evidence: "Exit drive averaged \(score) across your recent rides.",
                drill: "Once the exit is visible, pick the bike up and add throttle in one progressive motion. Never chase the score with pace.",
                target: "Fewer flat-exit patterns at the same comfortable pace"
            )
        case .brakingFeel:
            return RiderCraftFocus(
                kind: weakest.0,
                title: "Progressive Braking",
                evidence: "Braking feel averaged \(score) across your recent rides.",
                drill: "Build pressure smoothly, hold only what you need, then release progressively before the corner.",
                target: "Smoother pressure changes, not harder braking"
            )
        case .throttleFeel:
            return RiderCraftFocus(
                kind: weakest.0,
                title: "Quiet Throttle",
                evidence: "Throttle feel averaged \(score) across your recent rides.",
                drill: "Use one deliberate roll-on rather than adding and backing off. Slower practice is better practice.",
                target: "Fewer abrupt drive zones"
            )
        case .consistency:
            return RiderCraftFocus(
                kind: weakest.0,
                title: "Repeatable Inputs",
                evidence: "Consistency averaged \(score) across your recent rides.",
                drill: "Use the same calm sequence on similar bends: view, brake, turn, settle, drive.",
                target: "More similar treatment of similar corners"
            )
        }
    }

    private func badges(from ride: Ride?) -> [RiderCraftBadge] {
        let craft = ride?.riderCraftSummary
        let scores = ride?.coachScores ?? [:]
        let counts = craft?.categoryCounts ?? [:]
        let corners = craft?.cornerCount ?? 0
        return [
            RiderCraftBadge(
                kind: .settledEntry,
                title: "Settled Entry",
                detail: "20+ corners with no braking-after-turn-in detection.",
                symbol: "checkmark.circle.fill",
                isEarned: corners >= 20 && counts[.brakeAfterTurnIn, default: 0] == 0
            ),
            RiderCraftBadge(
                kind: .smoothHands,
                title: "Smooth Hands",
                detail: "Braking and throttle smoothness both at least 80.",
                symbol: "hand.raised.fill",
                isEarned: (scores[RideCoachScore.Kind.brakingFeel.storageKey] ?? 0) >= 80 &&
                    (scores[RideCoachScore.Kind.throttleFeel.storageKey] ?? 0) >= 80
            ),
            RiderCraftBadge(
                kind: .repeatable,
                title: "Repeatable",
                detail: "Consistency at least 70 on the latest analysed ride.",
                symbol: "repeat.circle.fill",
                isEarned: (scores[RideCoachScore.Kind.consistency.storageKey] ?? 0) >= 70
            ),
            RiderCraftBadge(
                kind: .lateApexHabit,
                title: "Late Apex Habit",
                detail: "Awaiting validated blind-corner matching before this can be earned.",
                symbol: "arrow.turn.up.right",
                isEarned: false
            ),
            RiderCraftBadge(
                kind: .wetDiscipline,
                title: "Wet Discipline",
                detail: "Awaiting enough wet and dry rides for a fair personal comparison.",
                symbol: "cloud.rain.fill",
                isEarned: false
            )
        ]
    }
}
