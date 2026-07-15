import SwiftUI

struct RouteDistanceControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var targetDistanceKm: Double?
    let suggestedDistanceKm: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Target distance")
                        .font(MLFont.bodyEmphasised)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text(targetDistanceKm == nil ? "Automatic from mood and time" : "Overrides the time estimate")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
                Spacer(minLength: Spacing.sm)
                Toggle("Set target distance", isOn: overrideBinding)
                    .labelsHidden()
                    .tint(.mlAccent)
            }

            if targetDistanceKm != nil {
                VStack(spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(distanceBinding.wrappedValue.rounded()))")
                            .font(MLFont.displaySmall)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text("km")
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextSecondary)
                        Spacer()
                    }

                    Slider(
                        value: distanceBinding,
                        in: RoutePlanningLimits.distanceRange,
                        step: RoutePlanningLimits.distanceStep
                    )
                    .tint(.mlAccent)
                    .accessibilityLabel("Target distance")
                    .accessibilityValue("\(Int(distanceBinding.wrappedValue.rounded())) kilometres")
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Motion.springGentle, value: targetDistanceKm != nil)
    }

    private var overrideBinding: Binding<Bool> {
        Binding(
            get: { targetDistanceKm != nil },
            set: { enabled in
                Haptics.selection()
                targetDistanceKm = enabled ? roundedSuggestedDistance : nil
            }
        )
    }

    private var distanceBinding: Binding<Double> {
        Binding(
            get: { targetDistanceKm ?? roundedSuggestedDistance },
            set: { targetDistanceKm = $0 }
        )
    }

    private var roundedSuggestedDistance: Double {
        let clamped = min(max(suggestedDistanceKm, RoutePlanningLimits.distanceRange.lowerBound), RoutePlanningLimits.distanceRange.upperBound)
        return (clamped / RoutePlanningLimits.distanceStep).rounded() * RoutePlanningLimits.distanceStep
    }
}

struct CompassDirectionPicker: View {
    @Binding var selection: CompassDirection?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3)
    private let slots: [CompassSlot] = [
        .direction(.northWest), .direction(.north), .direction(.northEast),
        .direction(.west), .surprise, .direction(.east),
        .direction(.southWest), .direction(.south), .direction(.southEast)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Departure direction")
                        .font(MLFont.bodyEmphasised)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text("Biases the first part of the loop")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }
                Spacer(minLength: Spacing.sm)
                Text(selection?.title ?? "Surprise me")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlAccent)
            }

            LazyVGrid(columns: columns, spacing: Spacing.xs) {
                ForEach(slots) { slot in
                    directionButton(slot)
                }
            }
        }
    }

    private func directionButton(_ slot: CompassSlot) -> some View {
        let isSelected = slot.direction == selection && (selection != nil || slot == .surprise)
        return Button {
            Haptics.selection()
            withAnimation(Motion.springSnappy) {
                selection = slot.direction
            }
        } label: {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: slot.symbol)
                    .font(MLFont.headline)
                Text(slot.title)
                    .font(MLFont.kicker)
            }
            .foregroundStyle(isSelected ? Color.mlOnAccent : Color.mlTextSecondary)
            .frame(width: Layout.routeCompassButtonSize, height: Layout.routeCompassButtonSize)
            .background(isSelected ? Color.mlAccent : Color.mlSurfaceElevated, in: Circle())
            .contentShape(Circle())
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityLabel(slot.accessibilityTitle)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

private enum CompassSlot: Hashable, Identifiable {
    case direction(CompassDirection)
    case surprise

    var id: String {
        switch self {
        case .direction(let direction): direction.id
        case .surprise: "surprise"
        }
    }

    var direction: CompassDirection? {
        switch self {
        case .direction(let direction): direction
        case .surprise: nil
        }
    }

    var symbol: String {
        switch self {
        case .direction(let direction): direction.symbol
        case .surprise: "shuffle"
        }
    }

    var title: String {
        switch self {
        case .direction(let direction): direction.shortTitle
        case .surprise: "Any"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .direction(let direction): "Depart \(direction.title)"
        case .surprise: "Surprise me"
        }
    }
}

#Preview("Route planning controls") {
    struct PreviewContent: View {
        @State private var distance: Double? = 80
        @State private var direction: CompassDirection? = .northEast

        var body: some View {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    RouteDistanceControl(targetDistanceKm: $distance, suggestedDistanceKm: 72)
                    Divider().overlay(Color.mlHairline)
                    CompassDirectionPicker(selection: $direction)
                }
                .padding(Spacing.md)
            }
            .background(Color.mlBackground)
        }
    }
    return PreviewContent().preferredColorScheme(.dark)
}

#Preview("Route planning controls — automatic") {
    struct PreviewContent: View {
        @State private var distance: Double?
        @State private var direction: CompassDirection?

        var body: some View {
            VStack(spacing: Spacing.xl) {
                RouteDistanceControl(targetDistanceKm: $distance, suggestedDistanceKm: 35)
                CompassDirectionPicker(selection: $direction)
            }
            .padding(Spacing.md)
            .background(Color.mlBackground)
        }
    }
    return PreviewContent().preferredColorScheme(.dark)
}
