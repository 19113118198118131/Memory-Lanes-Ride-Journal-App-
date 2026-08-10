import MapKit
import SwiftUI

/// The single, memory-first replay surface for a completed ride.
struct RideStoryReplayView: View {
    let viewModel: RideDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var controlsVisible = true
    @State private var previousPlaybackSpeed: Double = 1
    @State private var momentDismissalTask: Task<Void, Never>?
    @State private var visibleMomentID: UUID?
    @State private var followsRider = false
    @State private var hasStartedPlayback = false
    @State private var cameraDistance: CLLocationDistance = 8_000
    @State private var lastCameraUpdate = Date.distantPast
    @State private var smoothedHeading: CLLocationDirection?
    @State private var displayedCoordinate: CLLocationCoordinate2D?
    @State private var displayedHeading: CLLocationDirection = 0
    @State private var cameraSetupTask: Task<Void, Never>?
    @State private var displayRouteCoordinates: [CLLocationCoordinate2D] = []
    @State private var momentEditor: MomentEditorContext?
    @State private var resumeAfterMomentEditor = false
    @State private var showsRiderSeekControls = false
    @State private var resumeAfterRiderSeek = false
    @State private var controlsDismissalTask: Task<Void, Never>?
    @AppStorage("rideStoryReplayRate") private var storedReplayRate = StoryReplayRate.cinematic.rawValue

    private var route: [Coordinate] { viewModel.mapDisplayRoute }
    private var replayPoints: [ReplayPoint] { viewModel.detail?.replayPoints ?? [] }
    private var routeCoordinates: [CLLocationCoordinate2D] {
        displayRouteCoordinates
    }
    private var completedCoordinates: [CLLocationCoordinate2D] {
        guard !replayPoints.isEmpty else { return [] }
        guard hasStartedPlayback else { return [replayPoints[0].coordinate.clCoordinate] }
        let endIndex = min(max(viewModel.playbackIndex, 0), replayPoints.count - 1)
        let sampleCount = min(endIndex + 1, 1_200)
        var coordinates: [CLLocationCoordinate2D]
        if sampleCount <= 1 {
            coordinates = [replayPoints[0].coordinate.clCoordinate]
        } else {
            let step = Double(endIndex) / Double(sampleCount - 1)
            coordinates = (0..<sampleCount).map { offset in
                let index = min(endIndex, Int((Double(offset) * step).rounded()))
                return replayPoints[index].coordinate.clCoordinate
            }
        }
        if let current = viewModel.currentReplayCoordinate?.clCoordinate {
            let last = coordinates.last
            let isDistinct = last.map {
                abs($0.latitude - current.latitude) > 0.000_000_1 ||
                    abs($0.longitude - current.longitude) > 0.000_000_1
            } ?? true
            if isDistinct { coordinates.append(current) }
        }
        return coordinates
    }
    private var maximumReplayIndex: Int { max(replayPoints.count - 1, 1) }
    private var isComplete: Bool {
        !replayPoints.isEmpty && viewModel.playbackIndex >= replayPoints.count - 1
    }
    private var progress: Double {
        guard let duration = replayPoints.last?.elapsedSeconds, duration > 0 else { return 0 }
        return min(max(viewModel.playbackElapsedSeconds / duration, 0), 1)
    }
    private var storySpeed: Double {
        let duration = replayPoints.last?.elapsedSeconds ?? 0
        return min(max(duration / 180, 1), 120)
    }
    private var effectiveStorySpeed: Double {
        storySpeed * replayRate.multiplier
    }
    private var replayRate: StoryReplayRate {
        StoryReplayRate(rawValue: storedReplayRate) ?? .cinematic
    }
    private var visibleMoment: Moment? {
        guard let visibleMomentID else { return nil }
        return viewModel.detail?.moments.first { $0.id == visibleMomentID }
    }
    private var elevationText: String {
        guard let elevation = viewModel.currentReplayPoint?.elevationMeters else { return "--" }
        return "\(Int(elevation.rounded())) m"
    }

    var body: some View {
        ZStack {
            storyMap
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.52), .clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if isComplete {
                completionOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                playbackChrome
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isComplete else { return }
            controlsVisible ? hideControls() : revealControls()
        }
        .onAppear(perform: beginStory)
        .onDisappear(perform: endStory)
        .onChange(of: viewModel.playbackIndex) { _, _ in
            updateRiderPresentation()
            updateVisibleMoment()
        }
        .onChange(of: replayPoints.count) { oldCount, newCount in
            guard oldCount == 0, newCount > 0 else { return }
            resetStoryToPreview()
        }
        .onChange(of: viewModel.playbackElapsedSeconds) { _, _ in
            updateRiderPresentation()
            updateCamera()
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            isPlaying ? scheduleControlsDismissal() : cancelControlsDismissal()
        }
        .onChange(of: isComplete) { _, complete in
            guard complete else { return }
            Haptics.success()
            withAnimation(reduceMotion ? nil : Motion.springGentle) {
                controlsVisible = true
            }
        }
        .sheet(item: $momentEditor, onDismiss: resumeStoryAfterMomentEditorIfNeeded) { context in
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
    }

    private var storyMap: some View {
        ZStack {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                if routeCoordinates.count > 1 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(
                            Color.mlTextPrimary.opacity(0.18),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }
                if completedCoordinates.count > 1 {
                    MapPolyline(coordinates: completedCoordinates)
                        .stroke(
                            Color.mlAccent.opacity(0.2),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(coordinates: completedCoordinates)
                        .stroke(
                            Color.mlAccent.opacity(0.92),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                        )
                }
                ForEach(viewModel.detail?.moments ?? []) { moment in
                    Annotation("", coordinate: moment.coordinate.clCoordinate) {
                        Button {
                            editMoment(moment)
                        } label: {
                            Image(systemName: moment.symbol)
                                .font(MLFont.caption)
                                .foregroundStyle(Color.mlOnAccent)
                                .frame(width: 30, height: 30)
                                .background(Color.mlAccent, in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 2))
                                .shadow(color: Color.mlAccent.opacity(0.35), radius: 8)
                                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                                .contentShape(Circle())
                        }
                        .buttonStyle(MLPressableButtonStyle())
                        .accessibilityLabel("Edit \(moment.title.isEmpty ? "moment" : moment.title)")
                        .accessibilityHint("Opens this moment without leaving the ride story")
                    }
                }
                if let coordinate = displayedCoordinate {
                    Annotation("Ride position", coordinate: coordinate) {
                        Button {
                            openRiderSeekControls()
                        } label: {
                            riderMarker
                        }
                        .buttonStyle(MLPressableButtonStyle())
                        .accessibilityLabel("Ride position")
                        .accessibilityHint("Opens controls to move backward or forward through the ride")
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { _ in suspendCameraFollow() }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in suspendCameraFollow() }
            )
        }
        .accessibilityLabel("Cinematic map replay of \(viewModel.ride.title)")
        .accessibilityHint("Pinch to zoom or drag to explore. Use Follow Rider to resume tracking.")
    }

    private var riderMarker: some View {
        ZStack {
            Circle()
                .fill(Color.mlAccent.opacity(0.16))
                .frame(width: 46, height: 46)
            Circle()
                .stroke(Color.mlAccent.opacity(0.38), lineWidth: 1)
                .frame(width: 38, height: 38)
            Image(systemName: "location.north.fill")
                .font(MLFont.callout)
                .foregroundStyle(Color.mlOnAccent)
                .frame(width: 29, height: 29)
                .background(Color.mlAccent, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.84), lineWidth: 1.5))
                .rotationEffect(.degrees(displayedHeading))
        }
        .shadow(color: Color.mlAccent.opacity(0.28), radius: 12)
        .animation(reduceMotion ? nil : Motion.spring, value: displayedHeading)
    }

    private var playbackChrome: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                topBar
                    .opacity(controlsVisible ? 1 : 0.35)

                cinematicTelemetry
                    .padding(.top, Spacing.sm)
                    .opacity(controlsVisible ? 1 : 0.22)
                    .offset(y: controlsVisible ? 0 : -8)

                Spacer()

                if let visibleMoment {
                    momentCard(visibleMoment)
                        .padding(.horizontal, Spacing.screenH)
                        .padding(.bottom, Spacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showsRiderSeekControls {
                    riderSeekControls
                        .padding(.horizontal, Spacing.screenH)
                        .padding(.bottom, Spacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                telemetryPanel
                    .opacity(controlsVisible ? 1 : 0)
                    .offset(y: controlsVisible ? 0 : 12)
                    .allowsHitTesting(controlsVisible)
            }

            cameraControls
                .padding(.trailing, Spacing.screenH)
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
        }
        .animation(reduceMotion ? nil : Motion.springGentle, value: controlsVisible)
        .animation(reduceMotion ? nil : Motion.springGentle, value: visibleMomentID)
        .animation(reduceMotion ? nil : Motion.springGentle, value: showsRiderSeekControls)
    }

    private var riderSeekControls: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                seekPlayback(by: -30)
            } label: {
                Image(systemName: "gobackward.30")
                    .font(MLFont.callout)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(MLPressableButtonStyle())
            .accessibilityLabel("Back 30 seconds")

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("RIDE POSITION").mlKicker()
                Text("Jump through the story")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }

            Spacer(minLength: 0)

            Button {
                seekPlayback(by: 30)
            } label: {
                Image(systemName: "goforward.30")
                    .font(MLFont.callout)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(MLPressableButtonStyle())
            .accessibilityLabel("Forward 30 seconds")

            Button {
                closeRiderSeekControls()
            } label: {
                Image(systemName: "xmark")
                    .font(MLFont.caption)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(MLPressableButtonStyle())
            .accessibilityLabel("Close ride position controls")
        }
        .foregroundStyle(Color.mlTextPrimary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .stroke(Color.mlAccent.opacity(0.24), lineWidth: Layout.hairline)
        )
        .accessibilityElement(children: .contain)
    }

    private var cameraControls: some View {
        VStack(spacing: Spacing.xs) {
            cameraButton(
                systemImage: followsRider && hasStartedPlayback ? "location.fill" : "location",
                label: followsRider && hasStartedPlayback ? "Following rider" : "Follow rider"
            ) {
                hasStartedPlayback = true
                followsRider = true
                Haptics.selection()
                updateCamera(force: true)
            }

            cameraButton(systemImage: "plus.magnifyingglass", label: "Zoom in") {
                adjustZoom(by: 0.72)
            }

            cameraButton(systemImage: "minus.magnifyingglass", label: "Zoom out") {
                adjustZoom(by: 1.38)
            }
        }
        .padding(Spacing.xs)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: Layout.hairline))
    }

    private func cameraButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            revealControls()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(MLFont.callout)
                .foregroundStyle(
                    followsRider && hasStartedPlayback && systemImage == "location.fill"
                        ? Color.mlAccent
                        : Color.mlTextPrimary
                )
                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityLabel(label)
    }

    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(MLFont.headline)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(MLPressableButtonStyle())
            .accessibilityLabel("Close ride story")

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("RIDE STORY").mlKicker()
                Text(viewModel.ride.title)
                    .font(MLFont.headline)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Haptics.selection()
                revealControls()
                addMoment()
            } label: {
                Image(systemName: "mappin.and.ellipse")
                    .font(MLFont.callout)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(MLPressableButtonStyle())
            .accessibilityLabel("Add moment here")
            .accessibilityHint("Pins a memory to the current position in the ride")

            Text("\(Int((progress * 100).rounded()))%")
                .font(MLFont.monoSmall)
                .monospacedDigit()
                .foregroundStyle(Color.mlTextSecondary)
                .padding(.horizontal, Spacing.sm)
                .frame(height: Layout.minTouchTarget)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(Color.mlTextPrimary)
        .padding(.horizontal, Spacing.screenH)
        .padding(.top, Spacing.sm)
    }

    private var cinematicTelemetry: some View {
        HStack(spacing: 0) {
            instrumentMetric(viewModel.playbackSpeedText, label: "Speed")
            Divider()
                .overlay(Color.white.opacity(0.12))
                .frame(height: 34)
            instrumentMetric(elevationText, label: "Elevation")
            Divider()
                .overlay(Color.white.opacity(0.12))
                .frame(height: 34)
            instrumentMetric(viewModel.playbackProgressText, label: "Elapsed")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: Layout.hairline)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 8)
        .padding(.horizontal, Spacing.screenH)
        .accessibilityElement(children: .combine)
    }

    private func instrumentMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label.uppercased()).mlKicker()
            Text(value)
                .font(MLFont.monoSmall)
                .monospacedDigit()
                .foregroundStyle(Color.mlTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
    }

    private var telemetryPanel: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Button {
                    Haptics.selection()
                    revealControls()
                    toggleStoryPlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlOnAccent)
                        .frame(width: 52, height: 52)
                        .background(Color.mlAccent, in: Circle())
                }
                .buttonStyle(MLPressableButtonStyle())
                .accessibilityLabel(viewModel.isPlaying ? "Pause ride story" : "Play ride story")

                replaySpeedMenu

                VStack(spacing: Spacing.xs) {
                    replayTimeline

                    HStack {
                        storyMetric(viewModel.playbackProgressText, label: "Time")
                        Spacer()
                        storyMetric(viewModel.playbackDistanceText, label: "Distance")
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: Layout.hairline)
        )
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, max(Spacing.lg, Spacing.screenH))
    }

    private var replayTimeline: some View {
        Slider(
            value: Binding(
                get: { Double(viewModel.playbackIndex) },
                set: {
                    revealControls()
                    viewModel.scrubPlayback(to: Int($0.rounded()))
                }
            ),
            in: 0...Double(maximumReplayIndex),
            step: 1
        )
        .tint(.mlAccent)
        .overlay {
            GeometryReader { proxy in
                ForEach(viewModel.detail?.moments ?? []) { moment in
                    if let routeIndex = moment.routeIndex {
                        Circle()
                            .fill(Color.mlTextPrimary)
                            .frame(width: 5, height: 5)
                            .shadow(color: Color.mlAccent.opacity(0.6), radius: 3)
                            .position(
                                x: timelineX(
                                    for: routeIndex,
                                    width: proxy.size.width
                                ),
                                y: proxy.size.height / 2
                            )
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityHint("Saved moments are marked along the timeline")
    }

    private var replaySpeedMenu: some View {
        Menu {
            ForEach(StoryReplayRate.allCases) { rate in
                Button {
                    storedReplayRate = rate.rawValue
                    viewModel.setPlaybackSpeed(effectiveStorySpeed)
                    Haptics.selection()
                    revealControls()
                } label: {
                    if replayRate == rate {
                        Label(rate.title, systemImage: "checkmark")
                    } else {
                        Text(rate.title)
                    }
                }
            }
        } label: {
            VStack(spacing: 1) {
                Text(replayRate.shortTitle)
                    .font(MLFont.monoSmall)
                    .monospacedDigit()
                Text("PACE")
                    .font(MLFont.kicker)
                    .foregroundStyle(Color.mlTextTertiary)
            }
            .foregroundStyle(Color.mlTextPrimary)
            .frame(width: 52, height: 52)
            .background(Color.white.opacity(0.08), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: Layout.hairline))
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityLabel("Replay speed, \(replayRate.title)")
        .accessibilityHint("Choose how quickly this ride story plays")
    }

    private func storyMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(MLFont.monoSmall)
                .monospacedDigit()
                .foregroundStyle(Color.mlTextPrimary)
            Text(label).mlCaption()
        }
    }

    private func momentCard(_ moment: Moment) -> some View {
        Button {
            editMoment(moment)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: moment.symbol)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlAccent)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                    .background(Color.mlAccent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("SAVED MOMENT").mlKicker()
                    Text(moment.title.isEmpty ? "Pinned moment" : moment.title)
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                    if !moment.note.isEmpty {
                        Text(moment.note)
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlTextSecondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: Spacing.sm) {
                        if let speed = moment.speedKmh {
                            momentTelemetry("\(Int(speed.rounded())) km/h", systemImage: "speedometer")
                        }
                        if let elevation = moment.elevationMeters {
                            momentTelemetry("\(Int(elevation.rounded())) m", systemImage: "mountain.2")
                        }
                    }
                    .padding(.top, Spacing.xxs)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextTertiary)
            }
        }
        .buttonStyle(MLPressableButtonStyle())
        .padding(Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlAccent.opacity(0.24), lineWidth: Layout.hairline)
        )
        .accessibilityLabel("Edit \(moment.title.isEmpty ? "pinned moment" : moment.title)")
        .accessibilityHint("Opens the moment editor and returns here when closed")
    }

    private func momentTelemetry(_ value: String, systemImage: String) -> some View {
        Label(value, systemImage: systemImage)
            .font(MLFont.caption)
            .foregroundStyle(Color.mlTextSecondary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(Color.black.opacity(0.18), in: Capsule())
    }

    private var completionOverlay: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark")
                .font(MLFont.title)
                .foregroundStyle(Color.mlOnAccent)
                .frame(width: 64, height: 64)
                .background(Color.mlAccent, in: Circle())
                .shadow(color: Color.mlAccent.opacity(0.35), radius: 20)

            VStack(spacing: Spacing.xs) {
                Text("RIDE COMPLETE").mlKicker()
                Text(viewModel.ride.title)
                    .font(MLFont.title)
                    .foregroundStyle(Color.mlTextPrimary)
                    .multilineTextAlignment(.center)
                Text(viewModel.ride.dateFormatted)
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
            }

            SegmentedMetric(items: viewModel.headlineStats)
                .padding(.horizontal, Spacing.md)

            HStack(spacing: Spacing.sm) {
                SecondaryButton(title: "Watch Again", systemImage: "arrow.counterclockwise") {
                    restartStory()
                }

                PrimaryButton(title: "Done", systemImage: "checkmark") {
                    dismiss()
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.screenH)
        .background(.ultraThinMaterial)
    }

    private func beginStory() {
        previousPlaybackSpeed = viewModel.playbackSpeed
        resetStoryToPreview()
    }

    private func resetStoryToPreview() {
        cameraDistance = reduceMotion ? 9_500 : 8_000
        hasStartedPlayback = false
        followsRider = false
        showsRiderSeekControls = false
        resumeAfterRiderSeek = false
        viewModel.pausePlayback()
        viewModel.scrubPlayback(to: 0)
        viewModel.setPlaybackSpeed(effectiveStorySpeed)
        prepareRouteGeometry()
        displayedCoordinate = replayPoints.first?.coordinate.clCoordinate
        displayedHeading = initialHeading
        cameraSetupTask?.cancel()
        cameraSetupTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            showRouteOverview()
        }
    }

    private func restartStory() {
        visibleMomentID = nil
        viewModel.scrubPlayback(to: 0)
        viewModel.setPlaybackSpeed(effectiveStorySpeed)
        hasStartedPlayback = true
        followsRider = true
        updateCamera(force: true)
        viewModel.togglePlayback()
    }

    private func toggleStoryPlayback() {
        if viewModel.isPlaying {
            viewModel.pausePlayback()
            return
        }
        hasStartedPlayback = true
        followsRider = true
        updateCamera(force: true)
        viewModel.togglePlayback()
    }

    private func addMoment() {
        openMomentEditor(moment: nil, routeIndex: viewModel.playbackIndex)
    }

    private func editMoment(_ moment: Moment) {
        openMomentEditor(
            moment: moment,
            routeIndex: moment.routeIndex ?? viewModel.playbackIndex
        )
    }

    private func openMomentEditor(moment: Moment?, routeIndex: Int) {
        resumeAfterMomentEditor = viewModel.isPlaying
        viewModel.pausePlayback()
        showsRiderSeekControls = false
        resumeAfterRiderSeek = false
        cancelControlsDismissal()
        momentDismissalTask?.cancel()
        visibleMomentID = nil
        momentEditor = MomentEditorContext(moment: moment, defaultRouteIndex: routeIndex)
    }

    private func resumeStoryAfterMomentEditorIfNeeded() {
        guard resumeAfterMomentEditor else { return }
        resumeAfterMomentEditor = false
        guard !isComplete else { return }
        hasStartedPlayback = true
        followsRider = true
        updateCamera(force: true)
        viewModel.togglePlayback()
    }

    private func timelineX(for routeIndex: Int, width: CGFloat) -> CGFloat {
        let thumbInset: CGFloat = 10
        let usableWidth = max(width - thumbInset * 2, 1)
        let fraction = min(max(Double(routeIndex) / Double(maximumReplayIndex), 0), 1)
        return thumbInset + usableWidth * CGFloat(fraction)
    }

    private func revealControls() {
        withAnimation(reduceMotion ? nil : Motion.springSnappy) {
            controlsVisible = true
        }
        scheduleControlsDismissal()
    }

    private func hideControls() {
        cancelControlsDismissal()
        withAnimation(reduceMotion ? nil : Motion.springGentle) {
            controlsVisible = false
        }
    }

    private func scheduleControlsDismissal() {
        cancelControlsDismissal()
        guard viewModel.isPlaying, momentEditor == nil, !showsRiderSeekControls, !isComplete else { return }
        controlsDismissalTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, viewModel.isPlaying else { return }
            hideControls()
        }
    }

    private func cancelControlsDismissal() {
        controlsDismissalTask?.cancel()
        controlsDismissalTask = nil
    }

    private func prepareRouteGeometry() {
        let replayRoute = replayPoints.map(\.coordinate.clCoordinate)
        let source = replayRoute.count > 1 ? replayRoute : route.clCoordinates
        displayRouteCoordinates = AnalyticsDisplaySampler.sample(source, limit: 1_200)
    }

    private func endStory() {
        cameraSetupTask?.cancel()
        momentDismissalTask?.cancel()
        cancelControlsDismissal()
        viewModel.pausePlayback()
        viewModel.setPlaybackSpeed(previousPlaybackSpeed)
    }

    private func openRiderSeekControls() {
        resumeAfterRiderSeek = viewModel.isPlaying
        viewModel.pausePlayback()
        cancelControlsDismissal()
        revealControls()
        withAnimation(reduceMotion ? nil : Motion.springSnappy) {
            showsRiderSeekControls = true
        }
        Haptics.selection()
    }

    private func closeRiderSeekControls() {
        withAnimation(reduceMotion ? nil : Motion.springGentle) {
            showsRiderSeekControls = false
        }
        guard resumeAfterRiderSeek, !isComplete else {
            resumeAfterRiderSeek = false
            return
        }
        resumeAfterRiderSeek = false
        hasStartedPlayback = true
        viewModel.togglePlayback()
    }

    private func seekPlayback(by seconds: TimeInterval) {
        guard let duration = replayPoints.last?.elapsedSeconds, duration > 0 else { return }
        let targetElapsed = min(max(viewModel.playbackElapsedSeconds + seconds, 0), duration)
        let targetIndex = replayPoints.indices.min { lhs, rhs in
            abs(replayPoints[lhs].elapsedSeconds - targetElapsed) <
                abs(replayPoints[rhs].elapsedSeconds - targetElapsed)
        } ?? 0
        hasStartedPlayback = true
        viewModel.scrubPlayback(to: targetIndex)
        updateRiderPresentation(force: true)
        updateCamera(force: true)
        Haptics.selection()
    }

    private func updateRiderPresentation(force: Bool = false) {
        guard let coordinate = viewModel.currentReplayCoordinate else { return }
        let lookAhead = max(replayPoints.count / 300, 4)
        let nextIndex = min(viewModel.playbackIndex + lookAhead, replayPoints.count - 1)
        let next = replayPoints.indices.contains(nextIndex) ? replayPoints[nextIndex].coordinate : coordinate
        let heading = smoothHeading(bearing(from: coordinate, to: next), force: force)
        displayedCoordinate = coordinate.clCoordinate
        withAnimation(reduceMotion ? nil : Motion.springSnappy) {
            displayedHeading = heading
        }
    }

    private func updateCamera(force: Bool = false) {
        guard followsRider else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastCameraUpdate) >= 0.045 else { return }
        guard let coordinate = viewModel.currentReplayCoordinate else { return }
        lastCameraUpdate = now

        let center = coordinate.clCoordinate
        let camera = MapCamera(
            centerCoordinate: center,
            distance: cameraDistance,
            heading: 0,
            pitch: reduceMotion ? 0 : 42
        )
        cameraPosition = .camera(camera)
    }

    private func suspendCameraFollow() {
        guard followsRider else { return }
        followsRider = false
        Haptics.selection()
    }

    private func adjustZoom(by factor: Double) {
        cameraDistance = min(max(cameraDistance * factor, 350), 12_000)
        hasStartedPlayback = true
        followsRider = true
        Haptics.selection()
        updateCamera(force: true)
    }

    private var initialHeading: CLLocationDirection {
        guard replayPoints.count > 1 else { return 0 }
        let lookAheadIndex = min(max(replayPoints.count / 240, 6), replayPoints.count - 1)
        return bearing(
            from: replayPoints[0].coordinate,
            to: replayPoints[lookAheadIndex].coordinate
        )
    }

    private func showRouteOverview() {
        guard !displayRouteCoordinates.isEmpty else {
            cameraPosition = .automatic
            return
        }
        var mapRect = MKMapRect.null
        for coordinate in displayRouteCoordinates {
            let point = MKMapPoint(coordinate)
            mapRect = mapRect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        guard !mapRect.isNull, !mapRect.isEmpty else {
            cameraPosition = .automatic
            return
        }
        let horizontalInset = max(mapRect.size.width * 0.18, 800)
        let verticalInset = max(mapRect.size.height * 0.24, 800)
        cameraPosition = .rect(
            mapRect.insetBy(dx: -horizontalInset, dy: -verticalInset)
        )
    }

    private func smoothHeading(_ target: CLLocationDirection, force: Bool) -> CLLocationDirection {
        guard let previous = smoothedHeading, !force, !reduceMotion else {
            smoothedHeading = target
            return target
        }
        let delta = ((target - previous + 540).truncatingRemainder(dividingBy: 360)) - 180
        let value = (previous + delta * 0.28 + 360).truncatingRemainder(dividingBy: 360)
        smoothedHeading = value
        return value
    }

    private func updateVisibleMoment() {
        let moments = viewModel.detail?.moments ?? []
        let threshold = max(replayPoints.count / 160, 8)
        guard let moment = moments.first(where: {
            guard let routeIndex = $0.routeIndex else { return false }
            return abs(routeIndex - viewModel.playbackIndex) <= threshold
        }) else {
            return
        }
        guard visibleMomentID != moment.id else { return }
        visibleMomentID = moment.id
        Haptics.selection()
        momentDismissalTask?.cancel()
        momentDismissalTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : Motion.springGentle) {
                visibleMomentID = nil
            }
        }
    }

    private func bearing(from start: Coordinate, to end: Coordinate) -> CLLocationDirection {
        let startLat = start.latitude * .pi / 180
        let endLat = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(endLat)
        let x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

private enum StoryReplayRate: Double, CaseIterable, Identifiable {
    case relaxed = 0.5
    case cinematic = 1
    case brisk = 2
    case quick = 4

    var id: Double { rawValue }
    var multiplier: Double { rawValue }
    var shortTitle: String { "\(rawValue.formatted(.number.precision(.fractionLength(0...1))))x" }

    var title: String {
        switch self {
        case .relaxed: "0.5x Relaxed"
        case .cinematic: "1x Cinematic"
        case .brisk: "2x Brisk"
        case .quick: "4x Quick"
        }
    }
}
