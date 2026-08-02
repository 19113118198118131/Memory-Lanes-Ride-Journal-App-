import SwiftUI

struct TurnByTurnGuidanceBanner: View {
    let state: TurnByTurnSessionState
    let snapshot: TurnByTurnSnapshot?
    var onRetry: (() -> Void)?

    init(
        state: TurnByTurnSessionState,
        snapshot: TurnByTurnSnapshot?,
        onRetry: (() -> Void)? = nil
    ) {
        self.state = state
        self.snapshot = snapshot
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                maneuverIcon

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    if let distance = leadingDistance {
                        Text(distance)
                            .font(MLFont.displaySmall)
                            .foregroundStyle(Color.mlTextPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Text(title)
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    if let notice = snapshot?.instruction?.notice, !notice.isEmpty {
                        Text(notice)
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlWarning)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Spacing.xs)

                if state == .navigating {
                    Image(systemName: snapshot?.state == .offRoute ? "exclamationmark.triangle.fill" : "location.fill")
                        .font(MLFont.callout)
                        .foregroundStyle(statusColor)
                        .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                }
            }

            if let upcomingInstruction = snapshot?.upcomingInstruction,
               state == .navigating || state == .rerouting {
                HStack(spacing: Spacing.sm) {
                    Text("Then")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                    Image(systemName: upcomingInstruction.maneuver.symbol)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlAccent)
                        .frame(width: Spacing.md)
                    Text(upcomingInstruction.text)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.top, Spacing.xs)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.mlHairline)
                        .frame(height: Layout.hairline)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if case .unavailable(let message) = state {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(message)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .lineLimit(2)
                    HStack(spacing: Spacing.sm) {
                        Label("Recording continues", systemImage: "record.circle")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                        Spacer(minLength: 0)
                        if let onRetry {
                            Button("Retry", action: onRetry)
                                .font(MLFont.bodyEmphasised)
                                .foregroundStyle(Color.mlWarning)
                                .frame(minWidth: Layout.minTouchTarget, minHeight: Layout.minTouchTarget)
                                .buttonStyle(MLPressableButtonStyle())
                        }
                    }
                }
                .padding(.top, Spacing.xs)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.mlHairline)
                        .frame(height: Layout.hairline)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(Spacing.md)
        .frame(minHeight: Layout.navigationManeuverSize + Spacing.md)
        .background(Color.mlSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(statusColor.opacity(0.5), lineWidth: Layout.hairline)
        )
        .shadow(color: .black.opacity(0.24), radius: Spacing.md, y: Spacing.xs)
        .animation(Motion.spring, value: snapshot?.instruction?.id)
        .animation(Motion.spring, value: snapshot?.upcomingInstruction?.id)
        .accessibilityElement(children: onRetry == nil ? .combine : .contain)
        .accessibilityLabel("Turn by turn guidance")
        .accessibilityValue(accessibilityValue)
    }

    private var maneuverIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(statusColor.opacity(0.16))
            if state == .loading || state == .rerouting {
                ProgressView().tint(statusColor)
            } else {
                Image(systemName: snapshot?.guidanceSymbol ?? "location.magnifyingglass")
                    .font(MLFont.title)
                    .foregroundStyle(statusColor)
            }
        }
        .frame(width: Layout.navigationManeuverSize, height: Layout.navigationManeuverSize)
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
            "Directions unavailable"
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
        let parts = [leadingDistance, title, snapshot?.upcomingInstruction?.text]
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
                upcomingInstruction: NavigationInstruction(
                    id: 2,
                    text: "Keep right toward Scenic Drive",
                    notice: nil,
                    maneuver: .keepRight,
                    startsAtMeters: 1_850
                ),
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
