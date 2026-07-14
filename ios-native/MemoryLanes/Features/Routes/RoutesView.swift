import SwiftUI

// MARK: - RoutesView
//
// Native route-planning home. Saved routes now come from Supabase; generated
// candidates remain local previews until the planner engine is ported.

struct RoutesView: View {
    @State private var viewModel: RoutesViewModel
    @State private var selectedMood = RouteMood.flowing
    @State private var selectedTime = RouteTime.ninety
    @State private var showCandidates = false
    let refreshTrigger: UUID
    let onSelectRoute: (PlannedRoute) -> Void

    init(
        viewModel: RoutesViewModel,
        refreshTrigger: UUID = UUID(),
        onSelectRoute: @escaping (PlannedRoute) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.refreshTrigger = refreshTrigger
        self.onSelectRoute = onSelectRoute
    }

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
                savedRoutesContent
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task(id: refreshTrigger) { await viewModel.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Ride setup").mlKicker()
            Text("Plan the next good road")
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
            Text("Pick a mood and time window, or open one of your saved planned routes.")
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
            SecondaryButton(title: "Refresh", systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh() }
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

            ForEach(RouteCandidate.candidates(mood: selectedMood, time: selectedTime)) { route in
                candidateCard(route)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var savedRoutesContent: some View {
        switch viewModel.state {
        case .loading:
            VStack(spacing: Spacing.md) {
                SkeletonBar(height: 260, radius: Radius.card).mlShimmer()
                SkeletonBar(height: 260, radius: Radius.card).mlShimmer()
            }
        case .loaded(let routes):
            LazyVStack(spacing: Spacing.md) {
                ForEach(routes) { route in
                    plannedRouteCard(route)
                }
            }
        case .empty:
            EmptyState(
                systemImage: "map",
                title: "No saved routes yet",
                message: "Plan a route in Memory Lanes and it will appear here."
            )
        case .failed(let message):
            EmptyState(
                systemImage: "wifi.exclamationmark",
                title: "Couldn’t load routes",
                message: message,
                actionTitle: "Try Again"
            ) {
                Task { await viewModel.load() }
            }
        }
    }

    private func plannedRouteCard(_ route: PlannedRoute) -> some View {
        Button {
            Haptics.selection()
            onSelectRoute(route)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                routeMap(route.route)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.xs) {
                            Text(route.title)
                                .font(MLFont.title2)
                                .foregroundStyle(Color.mlTextPrimary)
                                .lineLimit(2)
                            if route.isPublic {
                                Text("Shared")
                                    .font(MLFont.caption)
                                    .foregroundStyle(Color.mlOnAccent)
                                    .padding(.horizontal, Spacing.xs)
                                    .frame(height: 24)
                                    .background(Color.mlAccent, in: Capsule())
                            }
                        }
                        Text(route.summary)
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.mlAccent)
                }

                SegmentedMetric(items: [
                    .init(value: route.distanceText, unit: "km", label: "Distance"),
                    .init(value: route.estimatedTimeText, unit: "", label: "Time"),
                    .init(value: route.elevationText, unit: "m", label: "Ascent")
                ])
            }
            .padding(Spacing.md)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(MLPressableButtonStyle())
    }

    private func candidateCard(_ route: RouteCandidate) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            routeMap(route.preview)

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
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.mlAccent)
            }

            SegmentedMetric(items: [
                .init(value: route.distance, unit: "km", label: "Distance"),
                .init(value: route.time, unit: "", label: "Time"),
                .init(value: route.elevation, unit: "m", label: "Ascent")
            ])

            SecondaryButton(title: "Use This Route", systemImage: "checkmark.circle.fill") {
                Haptics.success()
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func routeMap(_ route: [Coordinate]) -> some View {
        Group {
            if route.count > 1 {
                RouteThumbnail(route: route)
            } else {
                ZStack {
                    Color.mlSurfaceElevated
                    Image(systemName: "map")
                        .font(MLFont.displaySmall)
                        .foregroundStyle(Color.mlTextTertiary)
                }
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

struct PlannedRouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var route: PlannedRoute
    @State private var sharePayload: RouteSharePayload?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    let routeService: any RouteServing
    let onStartRide: (PlannedRoute) -> Void
    let onChanged: () -> Void
    let onDeleted: () -> Void

    init(
        route: PlannedRoute,
        routeService: any RouteServing,
        onStartRide: @escaping (PlannedRoute) -> Void = { _ in },
        onChanged: @escaping () -> Void = {},
        onDeleted: @escaping () -> Void = {}
    ) {
        _route = State(initialValue: route)
        self.routeService = routeService
        self.onStartRide = onStartRide
        self.onChanged = onChanged
        self.onDeleted = onDeleted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if route.route.count > 1 {
                    MLMapView(route: route.route, fadeColor: .mlBackground)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(route.isPublic ? "Shared route" : "Saved route").mlKicker()
                    Text(route.title)
                        .font(MLFont.displayXL)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text(route.summary)
                        .font(MLFont.body)
                        .foregroundStyle(Color.mlTextSecondary)
                }

                SegmentedMetric(items: [
                    .init(value: route.distanceText, unit: "km", label: "Distance"),
                    .init(value: route.estimatedTimeText, unit: "", label: "Est. Time"),
                    .init(value: route.elevationText, unit: "m", label: "Ascent")
                ])
                .padding(.horizontal, Spacing.md)
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                )

                actionPanel

                if let errorMessage {
                    Text(errorMessage)
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlDanger)
                        .padding(Spacing.md)
                        .background(Color.mlDanger.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(title: "Waypoints")
                    ForEach(Array(route.waypoints.enumerated()), id: \.offset) { index, waypoint in
                        HStack(spacing: Spacing.md) {
                            Text("\(index + 1)")
                                .font(MLFont.monoSmall)
                                .foregroundStyle(Color.mlOnAccent)
                                .frame(width: 30, height: 30)
                                .background(Color.mlAccent, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(index == 0 ? "Start" : "Waypoint")
                                    .font(MLFont.callout)
                                    .foregroundStyle(Color.mlTextPrimary)
                                Text(String(format: "%.5f, %.5f", waypoint.latitude, waypoint.longitude))
                                    .font(MLFont.caption)
                                    .foregroundStyle(Color.mlTextSecondary)
                            }
                            Spacer()
                        }
                        .padding(Spacing.md)
                        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }
                }
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Route")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete this route?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Route", role: .destructive) {
                Task { await deleteRoute() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved route from your account.")
        }
    }

    private var actionPanel: some View {
        VStack(spacing: Spacing.md) {
            PrimaryButton(title: "Start Ride", systemImage: "location.north.line.fill") {
                Haptics.impact(.medium)
                onStartRide(route)
            }

            SecondaryButton(title: route.isPublic ? "Share Invite" : "Create Invite", systemImage: "square.and.arrow.up") {
                Task { await shareInvite() }
            }
            .disabled(isWorking)

            HStack(spacing: Spacing.md) {
                SecondaryButton(title: "Export GPX", systemImage: "square.and.arrow.down") {
                    exportGPX()
                }
                SecondaryButton(title: route.isPublic ? "Stop Sharing" : "Private", systemImage: route.isPublic ? "eye.slash" : "lock") {
                    Task { await stopSharing() }
                }
                .disabled(!route.isPublic || isWorking)
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Route", systemImage: "trash")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlDanger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Capsule().stroke(Color.mlDanger.opacity(0.4), lineWidth: Layout.hairline)
                    )
            }
            .buttonStyle(MLPressableButtonStyle())
            .disabled(isWorking)
        }
    }

    private func shareInvite() async {
        isWorking = true
        errorMessage = nil
        do {
            if !route.isPublic || route.shareToken == nil {
                route = try await routeService.setSharing(true, for: route)
                onChanged()
            }
            guard let url = route.inviteURL else {
                throw RouteActionError.missingInviteLink
            }
            Haptics.success()
            sharePayload = RouteSharePayload(items: [url])
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func stopSharing() async {
        guard route.isPublic else { return }
        isWorking = true
        errorMessage = nil
        do {
            route = try await routeService.setSharing(false, for: route)
            Haptics.success()
            onChanged()
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func deleteRoute() async {
        isWorking = true
        errorMessage = nil
        do {
            try await routeService.deleteRoute(route)
            Haptics.success()
            onDeleted()
            dismiss()
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func exportGPX() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(route.gpxFileName)
            try route.gpxText.write(to: url, atomically: true, encoding: .utf8)
            sharePayload = RouteSharePayload(items: [url])
        } catch {
            Haptics.error()
            errorMessage = "Could not prepare the GPX export."
        }
    }
}

private struct RouteSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private enum RouteActionError: LocalizedError {
    case missingInviteLink

    var errorDescription: String? {
        switch self {
        case .missingInviteLink:
            return "The route could not create an invite link."
        }
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

private struct RouteCandidate: Identifiable {
    let id = UUID()
    let title: String
    let distance: String
    let time: String
    let elevation: String
    let summary: String
    let preview: [Coordinate]

    static func candidates(mood: RouteMood, time: RouteTime) -> [RouteCandidate] {
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
    NavigationStack {
        RoutesView(viewModel: RoutesViewModel(routeService: PreviewRouteService()))
    }
    .preferredColorScheme(.dark)
}
