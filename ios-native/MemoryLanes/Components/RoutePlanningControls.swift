import SwiftUI

struct RouteStartSearchControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var provider: RouteStartLocationProvider

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.mlTextSecondary)
                TextField("Address, suburb, road or landmark", text: $provider.query)
                    .font(MLFont.body)
                    .foregroundStyle(Color.mlTextPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                if provider.isSearching {
                    ProgressView().tint(.mlAccent)
                } else if !provider.query.isEmpty {
                    Button {
                        provider.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.mlTextTertiary)
                            .mlHitTarget()
                    }
                    .buttonStyle(MLPressableButtonStyle())
                    .accessibilityLabel("Clear start search")
                }
                Button {
                    provider.useCurrentLocation()
                } label: {
                    Group {
                        if provider.isLocating {
                            ProgressView()
                                .tint(.mlAccent)
                        } else {
                            Image(systemName: "location.fill")
                                .foregroundStyle(Color.mlAccent)
                        }
                    }
                    .mlHitTarget()
                }
                .buttonStyle(MLPressableButtonStyle())
                .disabled(provider.isLocating)
                .accessibilityLabel(provider.isLocating ? "Finding current location" : "Use current location")
            }
            .padding(.leading, Spacing.md)
            .padding(.trailing, Spacing.xs)
            .frame(minHeight: Layout.minTouchTarget)
            .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .stroke(provider.coordinate == nil ? Color.mlHairline : Color.mlAccent.opacity(0.5), lineWidth: Layout.hairline)
            )

            if !provider.suggestions.isEmpty {
                VStack(spacing: .zero) {
                    ForEach(provider.suggestions) { suggestion in
                        Button {
                            Haptics.selection()
                            provider.selectSuggestion(suggestion)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(Color.mlAccent)
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(suggestion.title)
                                        .font(MLFont.callout)
                                        .foregroundStyle(Color.mlTextPrimary)
                                        .lineLimit(1)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(MLFont.caption)
                                            .foregroundStyle(Color.mlTextSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MLPressableButtonStyle())

                        if suggestion.id != provider.suggestions.last?.id {
                            Divider().overlay(Color.mlHairline)
                        }
                    }
                }
                .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if provider.query.isEmpty, !provider.recentPlaces.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Recent starts").mlKicker()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ForEach(provider.recentPlaces) { place in
                                Button {
                                    Haptics.selection()
                                    provider.selectRecentPlace(place)
                                } label: {
                                    Label(place.title, systemImage: "clock.arrow.circlepath")
                                        .font(MLFont.caption)
                                        .foregroundStyle(Color.mlTextSecondary)
                                        .padding(.horizontal, Spacing.sm)
                                        .frame(minHeight: Layout.minTouchTarget)
                                        .background(Color.mlSurfaceElevated, in: Capsule())
                                }
                                .buttonStyle(MLPressableButtonStyle())
                            }
                        }
                    }
                }
            }

            if let selectedPlace = provider.selectedPlace {
                Label(selectedPlace.title, systemImage: "checkmark.circle.fill")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlAccent)
            }
        }
        .animation(reduceMotion ? nil : Motion.springGentle, value: provider.suggestions)
    }
}

struct RoutePlanningProgressView: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "map.fill")
                .font(MLFont.title2)
                .foregroundStyle(Color.mlAccent)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Exploring nearby roads")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                Text("Checking road-only loops, travel time and route character.")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Planning route. Exploring nearby roads.")
    }
}

struct RoutePlanningFailureView: View {
    let title: String
    let message: String
    let retryTitle: String
    var retrySystemImage = "arrow.clockwise"
    let onRetry: () -> Void
    let onReset: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "map.fill")
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlWarning)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text(message)
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PrimaryButton(title: retryTitle, systemImage: retrySystemImage, action: onRetry)

            if let onReset {
                Button {
                    onReset()
                } label: {
                    Label("Reset options", systemImage: "arrow.counterclockwise")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                        .frame(maxWidth: .infinity)
                        .mlHitTarget()
                }
                .buttonStyle(MLPressableButtonStyle())
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlWarning.opacity(0.35), lineWidth: Layout.hairline)
        )
    }
}

struct RouteCandidateInsightDisclosure: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    let route: RouteCandidate

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(route.character.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "road.lanes.curved.right")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                }

                Text(route.character.confidence.title)
                    .mlKicker()

                if let recommendation = route.recommendation {
                    Divider().overlay(Color.mlHairline)
                    ForEach(recommendation.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "checkmark.circle")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    Text("\(recommendation.confidence.rawValue.capitalized) confidence · based only on your rated rides")
                        .mlKicker()
                }
            }
            .padding(.top, Spacing.sm)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Why this route").mlKicker()
                    Text(route.character.label)
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Spacer(minLength: Spacing.sm)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    Text("\(route.character.score)")
                        .font(MLFont.mono)
                        .foregroundStyle(Color.mlAccent)
                    Text("/100")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextTertiary)
                }
            }
            .frame(minHeight: Layout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .tint(.mlAccent)
        .padding(.vertical, Spacing.xxs)
        .animation(reduceMotion ? nil : Motion.springGentle, value: isExpanded)
    }
}

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
                            .monospacedDigit()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: Set<CompassDirection>

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
                Text(selection.isEmpty ? "Surprise me" : "\(selection.count) selected")
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
        let isSelected = slot.direction.map(selection.contains) ?? selection.isEmpty
        return Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : Motion.springSnappy) {
                if let direction = slot.direction {
                    if selection.contains(direction) {
                        selection.remove(direction)
                    } else {
                        selection.insert(direction)
                    }
                } else {
                    selection.removeAll()
                }
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
        @State private var direction: Set<CompassDirection> = [.northEast, .north]

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
        @State private var direction: Set<CompassDirection> = []

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

#Preview("Route planner recovery") {
    VStack(spacing: Spacing.lg) {
        RoutePlanningProgressView()
        RoutePlanningFailureView(
            title: "No road-only loop yet",
            message: "Apple Maps could not build a usable loop from this setup.",
            retryTitle: "Try Again",
            onRetry: {},
            onReset: {}
        )
    }
    .padding(Spacing.md)
    .background(Color.mlBackground)
    .preferredColorScheme(.dark)
}
