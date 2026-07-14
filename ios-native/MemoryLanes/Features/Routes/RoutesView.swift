import SwiftUI

// MARK: - RoutesView
//
// Native route-planning home. Saved routes come from Supabase; generated
// candidates are built locally from the chosen start, mood, and time window.

struct RoutesView: View {
    @State private var viewModel: RoutesViewModel
    @StateObject private var startLocation = RouteStartLocationProvider()
    @State private var selectedMood = RouteMood.flowing
    @State private var selectedTime = RouteTime.ninety
    @State private var showCandidates = false
    @State private var routeCandidates: [RouteCandidate] = []
    @State private var routeSaveError: String?
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

                if let routeSaveError {
                    Text(routeSaveError)
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlDanger)
                        .padding(Spacing.md)
                        .background(Color.mlDanger.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
                generateCandidates()
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
                Text("Start").mlKicker()
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(startLocation.coordinate == nil ? "Sample start" : "Current location")
                            .font(MLFont.headline)
                            .foregroundStyle(Color.mlTextPrimary)
                        Text(startLocation.summary)
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        startLocation.useCurrentLocation()
                    } label: {
                        if startLocation.isLocating {
                            ProgressView()
                                .tint(.mlAccent)
                        } else {
                            Image(systemName: "location.fill")
                                .font(MLFont.headline)
                                .foregroundStyle(Color.mlAccent)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Color.mlSurfaceElevated, in: Circle())
                    .buttonStyle(MLPressableButtonStyle())
                    .accessibilityLabel("Use current location")
                }
                .padding(Spacing.md)
                .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                if let errorMessage = startLocation.errorMessage {
                    Text(errorMessage)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlDanger)
                }
            }

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
                generateCandidates()
            }

            ForEach(routeCandidates) { route in
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
                Task { await saveCandidate(route) }
            }
            .disabled(viewModel.isSavingRoute)
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

    private func saveCandidate(_ candidate: RouteCandidate) async {
        guard !viewModel.isSavingRoute else { return }
        routeSaveError = nil
        do {
            let route = try await viewModel.createRoute(candidate.draft)
            Haptics.success()
            withAnimation(Motion.spring) {
                showCandidates = false
            }
            onSelectRoute(route)
        } catch {
            Haptics.error()
            routeSaveError = error.localizedDescription
        }
    }

    private func generateCandidates() {
        routeSaveError = nil
        routeCandidates = RouteCandidate.candidates(
            mood: selectedMood,
            time: selectedTime,
            start: startLocation.coordinate ?? Self.sampleStart
        )
        withAnimation(Motion.spring) {
            showCandidates = true
        }
    }

    private static var sampleStart: Coordinate {
        SampleData.ridgeRoute.first ?? Coordinate(latitude: -36.8485, longitude: 174.7633)
    }
}

struct PlannedRouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var route: PlannedRoute
    @State private var sharePayload: RouteSharePayload?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingEditSheet = false
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
        .sheet(isPresented: $showingEditSheet) {
            RouteEditSheet(route: route, isSaving: isWorking) { title in
                await updateRoute(title)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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

            SecondaryButton(title: "Edit Route", systemImage: "pencil") {
                showingEditSheet = true
            }
            .disabled(isWorking)

            SecondaryButton(title: "Duplicate Route", systemImage: "plus.square.on.square") {
                Task { await duplicateRoute() }
            }
            .disabled(isWorking)

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

    private func updateRoute(_ draft: PlannedRouteDraft) async {
        isWorking = true
        errorMessage = nil
        do {
            route = try await routeService.updateRoute(draft, for: route)
            Haptics.success()
            onChanged()
            showingEditSheet = false
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func duplicateRoute() async {
        isWorking = true
        errorMessage = nil
        do {
            let copy = try await routeService.createRoute(route.draftCopy(title: "\(route.title) Copy"))
            route = copy
            Haptics.success()
            onChanged()
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isWorking = false
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

private struct RouteEditSheet: View {
    let route: PlannedRoute
    let isSaving: Bool
    let onSave: (PlannedRouteDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var waypoints: [Coordinate]

    init(route: PlannedRoute, isSaving: Bool, onSave: @escaping (PlannedRouteDraft) async -> Void) {
        self.route = route
        self.isSaving = isSaving
        self.onSave = onSave
        _title = State(initialValue: route.title)
        _waypoints = State(initialValue: route.editableWaypoints)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Route details").mlKicker()
                    Text("Edit Route")
                        .font(MLFont.display)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text("Rename the route, reorder stops, or add a midpoint stop. Saving rebuilds the route line used by GPX export and ride recording.")
                        .font(MLFont.body)
                        .foregroundStyle(Color.mlTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Name").mlKicker()
                    TextField("Route name", text: $title)
                        .font(MLFont.body)
                        .foregroundStyle(Color.mlTextPrimary)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 52)
                        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                        )
                        .disabled(isSaving)
                }

                RouteThumbnail(route: previewRoute)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        SectionHeader(title: "Waypoints")
                        Spacer()
                        Button {
                            addMidpoint()
                        } label: {
                            Image(systemName: "plus")
                                .font(MLFont.headline)
                                .foregroundStyle(Color.mlAccent)
                                .frame(width: 40, height: 40)
                                .background(Color.mlSurfaceElevated, in: Circle())
                        }
                        .buttonStyle(MLPressableButtonStyle())
                        .disabled(isSaving || waypoints.count < 2)
                        .accessibilityLabel("Add waypoint")
                    }

                    ForEach(Array(waypoints.enumerated()), id: \.offset) { index, waypoint in
                        waypointRow(index: index, waypoint: waypoint)
                    }
                }

                HStack(spacing: Spacing.md) {
                    SecondaryButton(title: "Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSaving)

                    PrimaryButton(title: "Save", systemImage: "checkmark", isLoading: isSaving) {
                        Task { await onSave(editedDraft) }
                    }
                    .disabled(!canSave)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mlBackground)
    }

    private func waypointRow(index: Int, waypoint: Coordinate) -> some View {
        HStack(spacing: Spacing.md) {
            Text("\(index + 1)")
                .font(MLFont.monoSmall)
                .foregroundStyle(Color.mlOnAccent)
                .frame(width: 30, height: 30)
                .background(Color.mlAccent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(index == 0 ? "Start" : (index == waypoints.count - 1 ? "Finish" : "Stop"))
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(String(format: "%.5f, %.5f", waypoint.latitude, waypoint.longitude))
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }

            Spacer()

            Button {
                moveWaypoint(from: index, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0 || isSaving)

            Button {
                moveWaypoint(from: index, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == waypoints.count - 1 || isSaving)

            Button(role: .destructive) {
                removeWaypoint(at: index)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(waypoints.count <= 2 || isSaving)
        }
        .font(MLFont.callout)
        .foregroundStyle(Color.mlTextPrimary)
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var previewRoute: [Coordinate] {
        PlannedRouteDraft.routeLine(for: waypoints)
    }

    private var editedDraft: PlannedRouteDraft {
        PlannedRouteDraft.edited(
            title: cleanTitle,
            waypoints: waypoints,
            baseElevationM: route.elevationM
        )
    }

    private var cleanTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !cleanTitle.isEmpty && waypoints.count >= 2 && !isSaving && (
            cleanTitle != route.title || waypoints != route.editableWaypoints
        )
    }

    private func addMidpoint() {
        guard let first = waypoints.first, let last = waypoints.last else { return }
        let middle = Coordinate(
            latitude: (first.latitude + last.latitude) / 2,
            longitude: (first.longitude + last.longitude) / 2
        )
        let insertionIndex = max(waypoints.count - 1, 1)
        waypoints.insert(middle, at: insertionIndex)
    }

    private func moveWaypoint(from index: Int, offset: Int) {
        let target = index + offset
        guard waypoints.indices.contains(index), waypoints.indices.contains(target) else { return }
        waypoints.swapAt(index, target)
    }

    private func removeWaypoint(at index: Int) {
        guard waypoints.count > 2, waypoints.indices.contains(index) else { return }
        waypoints.remove(at: index)
    }
}

private extension PlannedRoute {
    var editableWaypoints: [Coordinate] {
        if waypoints.count >= 2 {
            return waypoints
        }
        guard let first = route.first, let last = route.last else { return waypoints }
        return [first, last]
    }
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

    var averageSpeedKmH: Double {
        switch self {
        case .flowing: 62
        case .twisty: 48
        case .scenic: 54
        case .relaxed: 44
        }
    }

    var elevationMetersPerKm: Double {
        switch self {
        case .flowing: 7
        case .twisty: 14
        case .scenic: 12
        case .relaxed: 5
        }
    }

    var bearingBias: Double {
        switch self {
        case .flowing: 18
        case .twisty: 47
        case .scenic: 82
        case .relaxed: 124
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

    var hours: Double {
        switch self {
        case .fortyFive: 0.75
        case .ninety: 1.5
        case .threeHours: 3
        case .halfDay: 4.5
        }
    }
}

private struct RouteCandidate: Identifiable {
    let id = UUID()
    let title: String
    let distanceKm: Double
    let time: String
    let elevationM: Double
    let summary: String
    let preview: [Coordinate]

    var distance: String {
        String(format: "%.1f", distanceKm)
    }

    var elevation: String {
        String(format: "%.0f", elevationM)
    }

    var draft: PlannedRouteDraft {
        PlannedRouteDraft(
            title: title,
            distanceKm: distanceKm,
            elevationM: elevationM,
            waypoints: waypoints,
            route: preview
        )
    }

    private var waypoints: [Coordinate] {
        guard let first = preview.first, let last = preview.last else { return [] }
        guard preview.count > 2 else { return [first, last] }
        return [first, preview[preview.count / 2], last]
    }

    static func candidates(mood: RouteMood, time: RouteTime, start: Coordinate) -> [RouteCandidate] {
        let targetDistance = mood.averageSpeedKmH * time.hours
        return [
            makeCandidate(
                title: "\(mood.title) Loop",
                mood: mood,
                time: time,
                start: start,
                targetDistanceKm: targetDistance,
                bearingOffset: mood.bearingBias,
                summary: "Balanced loop · generated from your route setup"
            ),
            makeCandidate(
                title: "\(mood.title) Alternate",
                mood: mood,
                time: time,
                start: start,
                targetDistanceKm: targetDistance * 0.86,
                bearingOffset: mood.bearingBias + 96,
                summary: "Shorter option · different roads home"
            )
        ]
    }

    private static func makeCandidate(
        title: String,
        mood: RouteMood,
        time: RouteTime,
        start: Coordinate,
        targetDistanceKm: Double,
        bearingOffset: Double,
        summary: String
    ) -> RouteCandidate {
        let anchors = routeAnchors(start: start, distanceKm: targetDistanceKm, bearingOffset: bearingOffset)
        let route = densifiedRoute(anchors)
        let distanceKm = route.totalDistanceKm
        return RouteCandidate(
            title: title,
            distanceKm: distanceKm,
            time: time.title,
            elevationM: distanceKm * mood.elevationMetersPerKm,
            summary: summary,
            preview: route
        )
    }

    private static func routeAnchors(start: Coordinate, distanceKm: Double, bearingOffset: Double) -> [Coordinate] {
        let leg = max(distanceKm / 5.2, 1.8)
        let first = start.projected(distanceKm: leg, bearingDegrees: bearingOffset)
        let second = first.projected(distanceKm: leg * 0.82, bearingDegrees: bearingOffset + 68)
        let third = second.projected(distanceKm: leg * 1.05, bearingDegrees: bearingOffset + 152)
        let fourth = third.projected(distanceKm: leg * 0.76, bearingDegrees: bearingOffset + 232)
        return [start, first, second, third, fourth, start]
    }

    private static func densifiedRoute(_ anchors: [Coordinate]) -> [Coordinate] {
        guard anchors.count > 1 else { return anchors }
        var route: [Coordinate] = []
        for index in anchors.indices.dropLast() {
            let from = anchors[index]
            let to = anchors[index + 1]
            let steps = 16
            for step in 0..<steps {
                let progress = Double(step) / Double(steps)
                route.append(from.interpolated(to: to, progress: progress))
            }
        }
        if let last = anchors.last {
            route.append(last)
        }
        return route
    }
}

private extension Coordinate {
    func projected(distanceKm: Double, bearingDegrees: Double) -> Coordinate {
        let earthRadiusKm = 6371.0
        let angularDistance = distanceKm / earthRadiusKm
        let bearing = bearingDegrees * .pi / 180
        let startLat = latitude * .pi / 180
        let startLon = longitude * .pi / 180

        let endLat = asin(
            sin(startLat) * cos(angularDistance) +
            cos(startLat) * sin(angularDistance) * cos(bearing)
        )
        let endLon = startLon + atan2(
            sin(bearing) * sin(angularDistance) * cos(startLat),
            cos(angularDistance) - sin(startLat) * sin(endLat)
        )

        return Coordinate(
            latitude: endLat * 180 / .pi,
            longitude: endLon * 180 / .pi
        )
    }

    func interpolated(to other: Coordinate, progress: Double) -> Coordinate {
        Coordinate(
            latitude: latitude + (other.latitude - latitude) * progress,
            longitude: longitude + (other.longitude - longitude) * progress
        )
    }

    func distanceKm(to other: Coordinate) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let startLat = latitude * .pi / 180
        let endLat = other.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            sin(dLon / 2) * sin(dLon / 2) * cos(startLat) * cos(endLat)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }
}

private extension Array where Element == Coordinate {
    var totalDistanceKm: Double {
        guard count > 1 else { return 0 }
        return zip(self, dropFirst()).reduce(0) { total, pair in
            total + pair.0.distanceKm(to: pair.1)
        }
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
