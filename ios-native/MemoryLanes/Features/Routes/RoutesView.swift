import SwiftUI

// MARK: - RoutesView
//
// Native version of the route-planning home: saved routes, a goal-first setup
// card, and generated route candidates. The route engine will replace the local
// sample data later; the interaction shape is here now.

struct RoutesView: View {
    @State private var selectedMood = RouteMood.flowing
    @State private var selectedTime = RouteTime.ninety
    @State private var showCandidates = false

    private let savedRoutes = PlannedRoute.sample

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                header
                actionRow
                setupCard

                if showCandidates {
                    candidates
                }

                SectionHeader(title: "Saved Routes")
                LazyVStack(spacing: Spacing.md) {
                    ForEach(savedRoutes) { route in
                        plannedRouteCard(route)
                    }
                }
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Ride setup").mlKicker()
            Text("Plan the next good road")
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
            Text("Pick a mood and time window. Memory Lanes will suggest loops that fit the way you want to ride.")
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionRow: some View {
        HStack(spacing: Spacing.md) {
            PrimaryButton(title: "Plan Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill") {
                Haptics.impact(.medium)
                withAnimation(Motion.spring) { showCandidates = true }
            }
            SecondaryButton(title: "Just Ride", systemImage: "location.north.line.fill") {
                Haptics.selection()
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Route setup")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Mood").mlKicker()
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(RouteMood.allCases) { mood in
                        ChoiceChip(title: mood.title, systemImage: mood.symbol, isSelected: selectedMood == mood) {
                            withAnimation(Motion.springSnappy) { selectedMood = mood }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Time").mlKicker()
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(RouteTime.allCases) { time in
                        ChoiceChip(title: time.title, systemImage: "clock", isSelected: selectedTime == time) {
                            withAnimation(Motion.springSnappy) { selectedTime = time }
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private var candidates: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Route Candidates", actionTitle: "Regenerate") {
                Haptics.selection()
            }

            ForEach(PlannedRoute.candidates(mood: selectedMood, time: selectedTime)) { route in
                plannedRouteCard(route, isCandidate: true)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func plannedRouteCard(_ route: PlannedRoute, isCandidate: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            RouteThumbnail(route: route.preview)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(route.title)
                        .font(MLFont.title2)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text(route.summary)
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                }
                Spacer()
                Image(systemName: isCandidate ? "sparkles" : "chevron.right")
                    .foregroundStyle(Color.mlAccent)
            }

            SegmentedMetric(items: [
                .init(value: route.distance, unit: "km", label: "Distance"),
                .init(value: route.time, unit: "", label: "Time"),
                .init(value: route.elevation, unit: "m", label: "Ascent")
            ])

            if isCandidate {
                SecondaryButton(title: "Use This Route", systemImage: "checkmark.circle.fill") {
                    Haptics.success()
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }
}

// MARK: - Supporting Types

private enum RouteMood: String, CaseIterable, Identifiable {
    case flowing, twisty, scenic, relaxed
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .flowing: "waveform.path"
        case .twisty: "point.topleft.down.to.point.bottomright.curvepath"
        case .scenic: "mountain.2.fill"
        case .relaxed: "leaf.fill"
        }
    }
}

private enum RouteTime: String, CaseIterable, Identifiable {
    case fortyFive, ninety, threeHours, halfDay
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fortyFive: "45 min"
        case .ninety: "1.5 hr"
        case .threeHours: "3 hr"
        case .halfDay: "Half day"
        }
    }
}

private struct PlannedRoute: Identifiable {
    let id = UUID()
    let title: String
    let distance: String
    let time: String
    let elevation: String
    let summary: String
    let preview: [Coordinate]

    static let sample: [PlannedRoute] = [
        .init(title: "Ridge Coffee Loop", distance: "72.4", time: "1h 55m", elevation: "890", summary: "Loop · 8 waypoints · saved yesterday", preview: SampleData.ridgeRoute),
        .init(title: "Coast Range Sweepers", distance: "118.0", time: "3h 10m", elevation: "1,420", summary: "Scenic · avoids motorways", preview: SampleData.ridgeRoute.reversed())
    ]

    static func candidates(mood: RouteMood, time: RouteTime) -> [PlannedRoute] {
        [
            .init(title: "\(mood.title) Option 1", distance: time == .fortyFive ? "32.0" : "84.3", time: time.title, elevation: "760", summary: "Best match · smooth corners, low traffic", preview: SampleData.ridgeRoute),
            .init(title: "\(mood.title) Option 2", distance: time == .halfDay ? "146.8" : "69.5", time: time.title, elevation: "1,120", summary: "More elevation · quieter roads", preview: SampleData.ridgeRoute.reversed())
        ]
    }
}

private struct ChoiceChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(MLFont.callout)
                .foregroundStyle(isSelected ? Color.mlOnAccent : Color.mlTextPrimary)
                .padding(.horizontal, Spacing.sm)
                .frame(height: 40)
                .background(isSelected ? Color.mlAccent : Color.mlSurfaceElevated, in: Capsule())
                .overlay(Capsule().stroke(Color.mlHairline, lineWidth: Layout.hairline))
        }
        .buttonStyle(MLPressableButtonStyle(scale: 0.98))
    }
}

private struct FlowLayout<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: spacing)], spacing: spacing) {
                content
            }
        }
    }
}

#Preview {
    NavigationStack { RoutesView() }
        .preferredColorScheme(.dark)
}
