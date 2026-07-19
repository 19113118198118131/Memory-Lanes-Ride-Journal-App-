import SwiftUI

struct TurnByTurnGuidanceBanner: View {
    let state: TurnByTurnSessionState
    let snapshot: TurnByTurnSnapshot?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            maneuverIcon

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let distance = leadingDistance {
                    Text(distance)
                        .font(MLFont.title2)
                        .foregroundStyle(Color.mlTextPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text(title)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                    .lineLimit(2)
                if let notice = snapshot?.instruction?.notice, !notice.isEmpty {
                    Text(notice)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlWarning)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.xs)

            if let snapshot {
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text(snapshot.remainingDistanceText)
                        .font(MLFont.monoSmall)
                        .foregroundStyle(Color.mlTextPrimary)
                        .monospacedDigit()
                    Text(snapshot.etaText)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(minHeight: Spacing.xxl + Spacing.lg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(statusColor.opacity(0.42), lineWidth: Layout.hairline)
        )
        .shadow(color: .black.opacity(0.24), radius: Spacing.md, y: Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Turn by turn guidance")
        .accessibilityValue(accessibilityValue)
    }

    private var maneuverIcon: some View {
        ZStack {
            Circle().fill(statusColor.opacity(0.16))
            if state == .loading || state == .rerouting {
                ProgressView().tint(statusColor)
            } else {
                Image(systemName: snapshot?.guidanceSymbol ?? "location.magnifyingglass")
                    .font(MLFont.title2)
                    .foregroundStyle(statusColor)
            }
        }
        .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
    }

    private var leadingDistance: String? {
        guard state != .loading, state != .rerouting else { return nil }
        let value = snapshot?.maneuverDistanceText ?? ""
        return value.isEmpty ? nil : value
    }

    private var title: String {
        switch state {
        case .inactive:
            "Route guidance"
        case .loading:
            "Preparing road directions"
        case .rerouting:
            "Finding a way back"
        case .unavailable:
            "Following saved route"
        case .arrived:
            "You have arrived"
        case .navigating:
            snapshot?.guidanceTitle ?? "Continue on route"
        }
    }

    private var statusColor: Color {
        switch state {
        case .unavailable:
            .mlWarning
        case .arrived:
            .mlSuccess
        case .rerouting:
            .mlWarning
        case .inactive, .loading, .navigating:
            snapshot?.state == .offRoute ? .mlWarning : .mlAccent
        }
    }

    private var accessibilityValue: String {
        let parts = [leadingDistance, title, snapshot?.remainingDistanceText, snapshot?.etaText]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}

#Preview("Turn guidance") {
    VStack(spacing: Spacing.md) {
        TurnByTurnGuidanceBanner(
            state: .navigating,
            snapshot: TurnByTurnSnapshot(
                state: .onRoute,
                instruction: NavigationInstruction(
                    id: 1,
                    text: "Turn left onto Scenic Drive",
                    notice: nil,
                    maneuver: .left,
                    startsAtMeters: 1_200
                ),
                upcomingInstruction: nil,
                distanceToManeuverMeters: 280,
                remainingDistanceMeters: 12_400,
                remainingTravelTime: 1_080,
                progressPercent: 42,
                deviationMeters: 8,
                matchedDistanceMeters: 9_100
            )
        )
        TurnByTurnGuidanceBanner(state: .rerouting, snapshot: nil)
    }
    .padding()
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
