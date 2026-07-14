import SwiftUI

// MARK: - RideDetailView
//
// The ride's home: a full-bleed hero map, headline stats on a card that slides
// up over the map, an interactive elevation chart, and switchable sections for
// corners, moments, and weather. One-tap share renders a summary image.
//
// Assembled entirely from library components — the only bespoke work here is
// layout and the section switch.

struct RideDetailView: View {
    @State private var viewModel: RideDetailViewModel
    @State private var activityPayload: ActivityPayload?
    @State private var momentEditor: MomentEditorContext?
    @State private var showingCalibrationReview = false
    @State private var isRendering = false
    @State private var mapFocusRequest = 0
    @Environment(\.dismiss) private var dismiss

    private let heroHeight: CGFloat = 340

    init(viewModel: RideDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        heroMap
                            .frame(height: heroHeight)
                            .id("ride-detail-map")

                        content
                            .background(
                                Color.mlBackground
                                    .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
                            )
                            .offset(y: -28)
                            .padding(.bottom, -28)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .onChange(of: mapFocusRequest) { _, _ in
                    withAnimation(Motion.springSnappy) {
                        scrollProxy.scrollTo("ride-detail-map", anchor: .top)
                    }
                }
            }

            // Sibling of the ScrollView so it respects the top safe area while
            // the map stays full-bleed underneath it.
            floatingControls
        }
        .background(Color.mlBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .onDisappear { viewModel.pausePlayback() }
        .sheet(item: $activityPayload) { payload in
            ActivityView(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $momentEditor) { context in
            MomentEditorSheet(
                context: context,
                routeCount: viewModel.routeForMomentPinning.count,
                isSaving: viewModel.isSavingMoment,
                errorMessage: viewModel.momentErrorMessage,
                onSave: { title, note, routeIndex in
                    let saved = await viewModel.saveMoment(
                        editingID: context.moment?.id,
                        title: title,
                        note: note,
                        routeIndex: routeIndex
                    )
                    if saved {
                        Haptics.success()
                        momentEditor = nil
                    } else {
                        Haptics.error()
                    }
                },
                onDelete: context.moment.map { moment in
                    {
                        let deleted = await viewModel.deleteMoment(moment)
                        if deleted {
                            Haptics.success()
                            momentEditor = nil
                        } else {
                            Haptics.error()
                        }
                    }
                },
                onCancel: { momentEditor = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCalibrationReview) {
            RiderCraftCalibrationReviewView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Scrolling content

    @ViewBuilder
    private var heroMap: some View {
        let route = viewModel.routeForMomentPinning
        ZStack(alignment: .bottom) {
            if route.count > 1 {
                MLMapView(
                    route: route,
                    fadeColor: .mlBackground,
                    replayIndex: viewModel.mapReplayIndex,
                    replayCoordinate: viewModel.currentReplayCoordinate,
                    completedRoute: viewModel.completedReplayRoute,
                    guideRoute: viewModel.plannedGuideRoute
                )
            } else {
                ZStack {
                    Color.mlSurfaceElevated
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: "map")
                            .font(MLFont.display)
                            .foregroundStyle(Color.mlTextTertiary)
                        Text("Route unavailable")
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                }
            }

            if viewModel.canReplay {
                heroReplayControls
                    .padding(.horizontal, Spacing.screenH)
                    .padding(.bottom, Spacing.xl)
            }
        }
    }

    private var heroReplayControls: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                Haptics.selection()
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlOnAccent)
                    .frame(width: 38, height: 38)
                    .background(Color.mlAccent, in: Circle())
            }
            .buttonStyle(MLPressableButtonStyle())
            .accessibilityLabel(viewModel.isPlaying ? "Pause replay" : "Play replay")

            Slider(
                value: Binding(
                    get: { Double(viewModel.playbackIndex) },
                    set: { viewModel.scrubPlayback(to: Int($0.rounded())) }
                ),
                in: 0...Double(maxReplayIndex),
                step: 1
            )
            .tint(.mlAccent)

            VStack(alignment: .trailing, spacing: 2) {
                Text(viewModel.playbackProgressText)
                    .font(MLFont.monoSmall)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(viewModel.playbackSpeedText)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }
            .frame(minWidth: 58, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: Layout.hairline)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            titleBlock

            SegmentedMetric(items: viewModel.headlineStats)
                .padding(.horizontal, Spacing.md)
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlHairline, lineWidth: Layout.hairline))

            MLSegmentedControl(
                items: RideDetailViewModel.Section.allCases,
                title: { $0.rawValue },
                selection: $viewModel.section,
                compact: true
            )

            sectionContent
        }
        .padding(.top, Spacing.lg)
        .mlScreenPadding()
        .padding(.bottom, Spacing.xxl)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Text(viewModel.ride.source.rawValue).mlKicker()
                if let location = viewModel.ride.locationName {
                    Text("· \(location)").mlKicker()
                }
            }
            Text(viewModel.ride.title)
                .font(MLFont.title)
                .foregroundStyle(Color.mlTextPrimary)
            Text(viewModel.ride.dateFormatted)
                .mlCaption()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.section {
        case .overview: overviewSection
        case .analytics: analyticsSection
        case .corners: cornersSection
        case .moments: momentsSection
        case .weather: weatherSection
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if viewModel.canReplay {
                replaySection
            }
            if let debrief = viewModel.detail?.debrief {
                debriefCard(debrief, trend: viewModel.detail?.coachTrend)
            }
            if let detail = viewModel.detail {
                RideFeedbackCard(
                    feedback: detail.feedback ?? .empty,
                    isSaving: viewModel.isSavingFeedback,
                    status: viewModel.feedbackStatus
                ) { feedback in
                    viewModel.queueFeedbackSave(feedback)
                }
            }
            if viewModel.ride.isPublic {
                publicShareCard
            }
            if let plannedRoute = viewModel.detail?.plannedRoute,
               let routeMatch = viewModel.detail?.routeMatch {
                routeMatchCard(route: plannedRoute, match: routeMatch)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.md),
                                GridItem(.flexible(), spacing: Spacing.md)],
                      spacing: Spacing.md) {
                StatCard(label: "Flow", value: viewModel.flowScoreText,
                         systemImage: "waveform.path.ecg")
                StatCard(label: "Ascent", value: viewModel.ride.elevationFormatted, unit: "m",
                         systemImage: "mountain.2")
            }
        }
    }

    @ViewBuilder
    private var analyticsSection: some View {
        switch viewModel.state {
        case .loading:
            VStack(spacing: Spacing.md) {
                SkeletonBar(height: 180, radius: Radius.card).mlShimmer()
                SkeletonBar(height: 220, radius: Radius.card).mlShimmer()
            }
        case .loaded(let detail):
            if detail.replayPoints.count > 2 {
                RideAnalyticsView(
                    analytics: detail.analytics ?? .empty,
                    replayPoints: detail.replayPoints,
                    coachScores: detail.coachScores,
                    debrief: detail.debrief,
                    coachTrend: detail.coachTrend
                ) { index in
                    focusReplayOnMap(index)
                }
            } else {
                EmptyState(
                    systemImage: "chart.xyaxis.line",
                    title: "Analytics unavailable",
                    message: "This ride needs a longer, time-stamped GPX track for reliable analysis."
                )
            }
        case .failed(let message):
            inlineError(message)
        }
    }

    private func coachScoreGrid(_ scores: [RideCoachScore]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Ride Coach")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.md),
                                GridItem(.flexible(), spacing: Spacing.md)],
                      spacing: Spacing.md) {
                ForEach(scores) { score in
                    CoachScoreCard(score: score)
                }
            }
        }
    }

    private var replaySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Replay", actionTitle: "Pin Current") {
                openMomentEditor(defaultRouteIndex: viewModel.playbackIndex)
            }

            HStack(alignment: .center, spacing: Spacing.md) {
                Button {
                    Haptics.selection()
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlOnAccent)
                        .frame(width: 48, height: 48)
                        .background(Color.mlAccent, in: Circle())
                }
                .buttonStyle(MLPressableButtonStyle())
                .accessibilityLabel(viewModel.isPlaying ? "Pause replay" : "Play replay")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(viewModel.playbackProgressText)
                            .font(MLFont.monoSmall)
                            .foregroundStyle(Color.mlTextPrimary)
                        Spacer()
                        Text(viewModel.playbackDistanceText)
                            .font(MLFont.monoSmall)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.playbackIndex) },
                            set: { viewModel.scrubPlayback(to: Int($0.rounded())) }
                        ),
                        in: 0...Double(maxReplayIndex),
                        step: 1
                    )
                    .tint(.mlAccent)
                }
            }

            HStack(spacing: Spacing.sm) {
                Label(viewModel.playbackSpeedText, systemImage: "speedometer")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                Spacer()
                ForEach([1.0, 2.0, 4.0], id: \.self) { speed in
                    Button {
                        Haptics.selection()
                        viewModel.setPlaybackSpeed(speed)
                    } label: {
                        Text("\(Int(speed))x")
                            .font(MLFont.caption)
                            .foregroundStyle(viewModel.playbackSpeed == speed ? Color.mlOnAccent : Color.mlTextPrimary)
                            .frame(width: 42, height: 30)
                            .background(
                                Capsule()
                                    .fill(viewModel.playbackSpeed == speed ? Color.mlAccent : Color.mlSurfaceElevated)
                            )
                    }
                    .buttonStyle(MLPressableButtonStyle())
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

    private var maxReplayIndex: Int {
        max((viewModel.detail?.replayPoints.count ?? 1) - 1, 1)
    }

    @ViewBuilder
    private var cornersSection: some View {
        switch viewModel.state {
        case .loading:
            VStack(spacing: Spacing.md) {
                SkeletonBar(height: 150, radius: Radius.card).mlShimmer()
                SkeletonBar(height: 150, radius: Radius.card).mlShimmer()
            }
        case .loaded(let detail):
            VStack(spacing: Spacing.md) {
                if RiderCraftFeature.isResearchPreviewEnabled,
                   let riderCraft = detail.riderCraft {
                    RiderCraftRideView(analysis: riderCraft) { index in
                        focusReplayOnMap(index)
                    }
                }

                if LimitPointFeature.isResearchPreviewEnabled,
                   let limitPointAnalysis = detail.limitPointAnalysis,
                   !limitPointAnalysis.corners.isEmpty {
                    LimitPointRideView(analysis: limitPointAnalysis) { index in
                        focusReplayOnMap(index)
                    }
                }

                #if DEBUG
                if !viewModel.calibrationReviewTargets.isEmpty {
                    calibrationReviewCard
                }
                #endif

                if detail.corners.isEmpty {
                    EmptyState(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                               title: "No corners analysed",
                               message: "This ride didn’t have enough cornering data to build tickets.")
                } else {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(detail.corners) { ticket in
                            CornerTicketCard(ticket: ticket) {
                                guard let index = ticket.replayIndex else { return }
                                focusReplayOnMap(index)
                            }
                        }
                    }
                }
            }
        case .failed(let message):
            inlineError(message)
        }
    }

    private func focusReplayOnMap(_ index: Int) {
        viewModel.scrubPlayback(to: index)
        viewModel.section = .overview
        mapFocusRequest += 1
    }

    private var calibrationReviewCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Development only").mlKicker()
                    Text("Rider Craft calibration")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Spacer()
                Text("\(viewModel.calibrationReviewedCount) / \(viewModel.calibrationReviewTargets.count)")
                    .font(MLFont.monoSmall)
                    .foregroundStyle(Color.mlInfo)
            }

            Text("Replay detector candidates and unflagged controls, then export the labels for threshold review.")
                .font(MLFont.callout)
                .foregroundStyle(Color.mlTextSecondary)

            Button {
                showingCalibrationReview = true
            } label: {
                Label("Open Calibration Review", systemImage: "scope")
                    .font(MLFont.bodyEmphasised)
                    .foregroundStyle(Color.mlOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.mlAccent, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(MLPressableButtonStyle())
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlInfo.opacity(0.45), lineWidth: Layout.hairline)
        )
    }

    private func routeMatchCard(route: PlannedRoute, match: RouteMatchSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Planned route").mlKicker()
                    Text(route.title)
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Spacer()
                Text(match.verdict)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlInfo)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(Color.mlInfo.opacity(0.12), in: Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      spacing: Spacing.sm) {
                compactMetric("On route", match.matchedText, "point.topleft.down.to.point.bottomright.curvepath")
                compactMetric("Distance", match.distanceDeltaText, "road.lanes")
                compactMetric("Avg drift", match.averageDeviationText, "scope")
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func compactMetric(_ label: String, _ value: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Image(systemName: systemImage)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)
            Text(value)
                .font(MLFont.monoSmall)
                .foregroundStyle(Color.mlTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label).mlKicker()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.mlSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }

    private var publicShareCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Public link").mlKicker()
                    Text("This ride is shareable")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                }
                Spacer()
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(Color.mlAccent)
            }
            if let url = viewModel.publicShareURL {
                Text(url.absoluteString)
                    .font(MLFont.monoSmall)
                    .foregroundStyle(Color.mlTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: Spacing.sm) {
                SecondaryButton(title: "Copy Link", systemImage: "square.and.arrow.up") {
                    sharePublicLink()
                }
                .disabled(viewModel.isUpdatingShareLink)
                SecondaryButton(title: "Stop Sharing", systemImage: "eye.slash") {
                    Task { @MainActor in
                        let revoked = await viewModel.revokePublicShareLink()
                        revoked ? Haptics.success() : Haptics.error()
                    }
                }
                .disabled(viewModel.isUpdatingShareLink)
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    @ViewBuilder
    private var momentsSection: some View {
        switch viewModel.state {
        case .loading:
            SkeletonBar(height: 72, radius: Radius.card).mlShimmer()
        case .loaded(let detail):
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader(
                    title: "Moments",
                    actionTitle: detail.moments.count < 5 ? "Add" : nil
                ) {
                    openMomentEditor()
                }

                if detail.moments.isEmpty {
                    EmptyState(systemImage: "sparkles",
                               title: "No moments captured",
                               message: "Pin a moment to remember exactly where it happened.")
                } else {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(detail.moments) { moment in
                            Button {
                                Haptics.selection()
                                openMomentEditor(moment)
                            } label: {
                                MomentRow(moment: moment)
                            }
                            .buttonStyle(MLPressableButtonStyle())
                        }
                    }
                }
            }
        case .failed(let message):
            inlineError(message)
        }
    }

    @ViewBuilder
    private var weatherSection: some View {
        switch viewModel.state {
        case .loading:
            SkeletonBar(height: 96, radius: Radius.card).mlShimmer()
        case .loaded(let detail):
            if let weather = detail.weather {
                WeatherStrip(weather: weather)
            } else {
                EmptyState(systemImage: "cloud.sun",
                           title: "No weather on record",
                           message: "We couldn’t find historical weather for this ride’s time and place.")
            }
        case .failed(let message):
            inlineError(message)
        }
    }

    private func debriefCard(_ text: String, trend: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("Ride Coach", systemImage: "quote.bubble.fill")
                .font(MLFont.headline)
                .foregroundStyle(Color.mlAccent)
            Text(text)
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let trend {
                Divider().overlay(Color.mlAccent.opacity(0.2))
                Label(trend, systemImage: "chart.line.uptrend.xyaxis")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlInfo)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mlAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .stroke(Color.mlAccent.opacity(0.25), lineWidth: Layout.hairline))
    }

    private func inlineError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(MLFont.callout)
            .foregroundStyle(Color.mlTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
    }

    // MARK: Floating controls

    private var floatingControls: some View {
        HStack {
            circleButton(systemImage: "chevron.left", label: "Back") { dismiss() }
            Spacer()
            circleButton(systemImage: viewModel.isUpdatingShareLink ? "hourglass" : "link",
                         label: "Share public link") {
                sharePublicLink()
            }
            .disabled(viewModel.isUpdatingShareLink)
            circleButton(systemImage: viewModel.isExportingGPX ? "hourglass" : "doc.badge.arrow.up",
                         label: "Export GPX") {
                exportGPX()
            }
            .disabled(viewModel.isExportingGPX)
            circleButton(systemImage: isRendering ? "hourglass" : "square.and.arrow.up",
                         label: "Share ride") {
                renderShareImage()
            }
            .disabled(isRendering)
        }
        .mlScreenPadding()
        .padding(.top, Spacing.xs)
    }

    private func circleButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.mlTextPrimary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.mlHairline, lineWidth: Layout.hairline))
        }
        .accessibilityLabel(label)
    }

    private func renderShareImage() {
        isRendering = true
        // ImageRenderer is main-actor bound; run on the next runloop tick so the
        // "rendering" state paints first, then hand the bitmap to the share sheet.
        Task { @MainActor in
            defer { isRendering = false }
            if let image = ShareCardRenderer.image(for: viewModel.ride) {
                Haptics.success()
                activityPayload = ActivityPayload(items: [
                    image,
                    ShareCardRenderer.summaryText(for: viewModel.ride)
                ])
            } else {
                Haptics.error()
            }
        }
    }

    private func sharePublicLink() {
        Task { @MainActor in
            do {
                let url = try await viewModel.publicShareLink()
                Haptics.success()
                activityPayload = ActivityPayload(items: [url])
            } catch {
                Haptics.error()
            }
        }
    }

    private func exportGPX() {
        Task { @MainActor in
            do {
                let url = try await viewModel.exportGPXFile()
                Haptics.success()
                activityPayload = ActivityPayload(items: [url])
            } catch {
                Haptics.error()
            }
        }
    }

    private func openMomentEditor(_ moment: Moment? = nil, defaultRouteIndex: Int? = nil) {
        let defaultIndex = defaultRouteIndex ?? viewModel.playbackIndex
        momentEditor = MomentEditorContext(moment: moment, defaultRouteIndex: moment?.routeIndex ?? defaultIndex)
    }
}

private struct MomentEditorContext: Identifiable {
    let id: UUID
    var moment: Moment?
    var defaultRouteIndex: Int

    init(moment: Moment?, defaultRouteIndex: Int) {
        self.id = moment?.id ?? UUID()
        self.moment = moment
        self.defaultRouteIndex = defaultRouteIndex
    }
}

private struct CoachScoreCard: View {
    let score: RideCoachScore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: score.kind.symbol)
                    .font(MLFont.caption)
                    .foregroundStyle(tint)
                Text(score.kind.title).mlKicker()
            }

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text("\(score.value)")
                    .font(MLFont.displaySmall)
                    .foregroundStyle(Color.mlTextPrimary)
                Text("/100")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mlSurfaceElevated)
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(score.value) / 100)
                }
            }
            .frame(height: 7)

            Text(score.caption)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private var tint: Color {
        if score.value >= 75 { return .mlSuccess }
        if score.value >= 50 { return .mlWarning }
        return .mlDanger
    }
}

private struct MomentEditorSheet: View {
    let context: MomentEditorContext
    let routeCount: Int
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (String, String, Int) async -> Void
    let onDelete: (() async -> Void)?
    let onCancel: () -> Void

    @State private var title: String
    @State private var note: String
    @State private var routeIndex: Int
    @State private var showingDeleteConfirmation = false

    init(
        context: MomentEditorContext,
        routeCount: Int,
        isSaving: Bool,
        errorMessage: String?,
        onSave: @escaping (String, String, Int) async -> Void,
        onDelete: (() async -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.context = context
        self.routeCount = routeCount
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _title = State(initialValue: context.moment?.title ?? "")
        _note = State(initialValue: context.moment?.note ?? "")
        _routeIndex = State(initialValue: min(max(context.defaultRouteIndex, 0), max(routeCount - 1, 0)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    form
                    if let errorMessage {
                        errorCard(errorMessage)
                    }
                    actions
                }
                .padding(.vertical, Spacing.md)
                .mlScreenPadding()
            }
            .background(Color.mlBackground)
            .navigationTitle(context.moment == nil ? "Add Moment" : "Edit Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .disabled(isSaving)
                }
            }
            .confirmationDialog(
                "Delete this moment?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Moment", role: .destructive) {
                    Task { await onDelete?() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the moment from this ride.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Ride memory").mlKicker()
            Text(context.moment == nil ? "Pin a new note" : "Tune this memory")
                .font(MLFont.display)
                .foregroundStyle(Color.mlTextPrimary)
            Text("Moments sync to your journal and stay attached to this ride.")
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Title").mlKicker()
                TextField("Summit stop", text: $title)
                    .font(MLFont.body)
                    .foregroundStyle(Color.mlTextPrimary)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 52)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                    )
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Note").mlKicker()
                TextEditor(text: $note)
                    .font(MLFont.body)
                    .foregroundStyle(Color.mlTextPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.sm)
                    .frame(minHeight: 132)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                    )
            }

            if routeCount > 1 {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text("Route position").mlKicker()
                        Spacer()
                        Text("\(routeIndex + 1) / \(routeCount)")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(routeIndex) },
                            set: { routeIndex = Int($0.rounded()) }
                        ),
                        in: 0...Double(max(routeCount - 1, 1)),
                        step: 1
                    )
                    .tint(.mlAccent)
                }
            }
        }
        .disabled(isSaving)
    }

    private var actions: some View {
        VStack(spacing: Spacing.md) {
            PrimaryButton(title: "Save Moment", systemImage: "tray.and.arrow.down.fill", isLoading: isSaving) {
                Task { await onSave(title, note, routeIndex) }
            }
            .disabled(isSaving)

            if onDelete != nil {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Moment", systemImage: "trash")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlDanger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Capsule().stroke(Color.mlDanger.opacity(0.4), lineWidth: Layout.hairline)
                        )
                }
                .buttonStyle(MLPressableButtonStyle())
                .disabled(isSaving)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(MLFont.callout)
            .foregroundStyle(Color.mlDanger)
            .padding(Spacing.md)
            .background(Color.mlDanger.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - Previews

#Preview("RideDetail — loaded") {
    NavigationStack {
        RideDetailView(viewModel: RideDetailViewModel(
            ride: SampleData.hero,
            rideService: PreviewRideService()
        ))
    }
    .preferredColorScheme(.dark)
}

#Preview("RideDetail — error") {
    NavigationStack {
        RideDetailView(viewModel: RideDetailViewModel(
            ride: SampleData.hero,
            rideService: PreviewRideService(failure: .notImplemented)
        ))
    }
    .preferredColorScheme(.dark)
}
