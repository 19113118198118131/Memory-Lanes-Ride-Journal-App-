import SwiftUI
import UIKit

// MARK: - RecordingView
//
// Native ride recording cockpit backed by Core Location. It records real device
// points, persists an interrupted draft, and creates GPX text when finished.

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: AuthSession
    let plannedRoute: PlannedRoute?
    let groupRideContext: GroupRideRecordingContext?
    let accessToken: @Sendable () async -> String?
    @ObservedObject var uploadQueue: PendingRideUploadCoordinator
    let onQueued: () -> Void

    @StateObject private var recorder = LiveRideRecorder()
    @StateObject private var liveSharing: GroupLiveSharingController
    @StateObject private var navigation: TurnByTurnNavigationController
    @State private var showingFinishConfirmation = false
    @State private var showingEndRideOptions = false
    @State private var finishedRide: RecordedRideResult?
    @State private var recoveredFinishedRide = false
    @State private var cameraMode: LiveRideCameraMode = .immersive
    @State private var followsRideCamera = true
    @State private var activeOfflineMapArea: OfflineMapArea?
    private let routeFollowAnalyzer = RouteFollowAnalyzer()

    init(
        session: AuthSession,
        plannedRoute: PlannedRoute?,
        groupRideContext: GroupRideRecordingContext? = nil,
        accessToken: @escaping @Sendable () async -> String?,
        uploadQueue: PendingRideUploadCoordinator,
        onQueued: @escaping () -> Void = {}
    ) {
        self.session = session
        self.plannedRoute = plannedRoute
        self.groupRideContext = groupRideContext
        self.accessToken = accessToken
        self.uploadQueue = uploadQueue
        self.onQueued = onQueued
        _liveSharing = StateObject(wrappedValue: GroupLiveSharingController(
            context: groupRideContext,
            service: GroupLiveLocationService(accessToken: accessToken)
        ))
        _navigation = StateObject(wrappedValue: TurnByTurnNavigationController(plannedRoute: plannedRoute))
    }

    var body: some View {
        ZStack(alignment: controlPanelAlignment) {
            mapLayer
                .ignoresSafeArea()
            controlPanel
        }
        .overlay(alignment: .top) {
            recorderHeader
        }
        .background(Color.mlBackground)
        .task {
            if let recovered = await recorder.prepareForPresentation() {
                recoveredFinishedRide = true
                finishedRide = recovered
            } else {
                await liveSharing.start()
                navigation.prepare(startingAt: recorder.points.last?.coordinate)
            }
        }
        .task {
            let areas = await MapLibreOfflineMapStore.shared.areas()
                .filter { $0.status == .complete }
            activateDownloadedMap(from: areas, near: recorder.points.last?.coordinate)
        }
        .task(id: groupRideContext?.shareToken) {
            await liveSharing.observeRiders()
        }
        .onChange(of: recorder.pointCount) { _, _ in
            guard let point = recorder.points.last else { return }
            if activeOfflineMapArea == nil {
                Task {
                    let areas = await MapLibreOfflineMapStore.shared.areas()
                        .filter { $0.status == .complete }
                    activateDownloadedMap(from: areas, near: point.coordinate)
                }
            }
            navigation.update(point)
            Task { await liveSharing.offer(point) }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            navigation.cancel()
            Task { await liveSharing.endSession() }
        }
        .alert("Finish ride?", isPresented: $showingFinishConfirmation) {
            Button("Keep Riding", role: .cancel) {}
            Button("Finish") {
                Haptics.success()
                Task {
                    await liveSharing.endSession()
                    recoveredFinishedRide = false
                    finishedRide = await recorder.finish()
                }
            }
        } message: {
            Text("Memory Lanes will stop recording, export a GPX backup, and let you save it to your journal.")
        }
        .alert("Finish this ride?", isPresented: $showingEndRideOptions) {
            Button("Keep Riding", role: .cancel) {}
            Button("Finish & Save") { finishRide() }
            Button("Discard Ride", role: .destructive) { discardActiveRide() }
        } message: {
            Text("Finish opens Save to Journal. Discard permanently deletes this recording from this iPhone.")
        }
        .sheet(item: $finishedRide) { result in
            RecordingFinishedSheet(
                result: result,
                session: session,
                plannedRoute: plannedRoute,
                uploadQueue: uploadQueue,
                isRecovered: recoveredFinishedRide,
                onSecured: {
                    await recorder.markCompletedRideSaved(result)
                },
                onQueued: onQueued,
                onDiscard: {
                    await recorder.discardCompletedRide(result)
                }
            ) {
                dismiss()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var mapLayer: some View {
        let latestPoint = recorder.points.last
        return Group {
            if latestPoint != nil || (plannedRoute?.route.count ?? 0) > 1 {
                if activeOfflineMapArea != nil {
                    OfflineLiveRideMapView(
                        recordedRoute: recorder.routePreview,
                        guideRoute: navigation.routeCoordinates.isEmpty
                            ? plannedRoute?.route ?? []
                            : navigation.routeCoordinates,
                        latestPoint: latestPoint,
                        liveRiders: liveSharing.riders,
                        cameraMode: cameraMode,
                        reduceMotion: reduceMotion,
                        followsCamera: $followsRideCamera
                    )
                    .overlay(Color.mlMapCockpitTint.allowsHitTesting(false))
                    .transition(.opacity)
                } else {
                    LiveRideMapView(
                        recordedRoute: recorder.routePreview,
                        guideRoute: navigation.routeCoordinates.isEmpty
                            ? plannedRoute?.route ?? []
                            : navigation.routeCoordinates,
                        latestPoint: latestPoint,
                        liveRiders: liveSharing.riders,
                        cameraMode: cameraMode,
                        reduceMotion: reduceMotion,
                        followsCamera: $followsRideCamera
                    )
                    .transition(.opacity)
                }
            } else {
                MLMapView(route: SampleData.ridgeRoute, fadeColor: .mlBackground)
                    .overlay(Color.black.opacity(0.42))
            }
        }
    }

    private var cameraControls: some View {
        HStack(spacing: Spacing.xs) {
            mapControlButton(
                symbol: cameraMode.symbol,
                label: "Map camera: \(cameraMode.title). Switch to \(cameraMode.next.title.lowercased())"
            ) {
                Haptics.selection()
                cameraMode = cameraMode.next
                followsRideCamera = true
            }

            mapControlButton(
                symbol: navigation.isVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: navigation.isVoiceEnabled ? "Mute spoken ride guidance" : "Enable spoken ride guidance"
            ) {
                Haptics.selection()
                navigation.isVoiceEnabled.toggle()
            }

            if !followsRideCamera {
                mapControlButton(symbol: "location.fill", label: "Recenter on ride") {
                    Haptics.selection()
                    followsRideCamera = true
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Motion.springSnappy, value: followsRideCamera)
        .animation(reduceMotion ? nil : Motion.springSnappy, value: navigation.isVoiceEnabled)
    }

    private func mapControlButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(MLFont.headline)
                .foregroundStyle(Color.mlTextPrimary)
                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                .background(Color.mlSurface.opacity(0.82), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.mlTextPrimary.opacity(0.12), lineWidth: Layout.hairline))
                .shadow(color: .black.opacity(0.2), radius: Spacing.sm, y: Spacing.xxs)
        }
        .buttonStyle(MLPressableButtonStyle())
        .accessibilityLabel(label)
    }

    private var recorderHeader: some View {
        VStack(spacing: Spacing.sm) {
            topBar
            if showsTurnByTurnBanner {
                TurnByTurnGuidanceBanner(
                    state: navigation.state,
                    snapshot: navigation.snapshot,
                    onRetry: navigation.state.isUnavailable ? {
                        Haptics.selection()
                        navigation.retry(startingAt: recorder.points.last?.coordinate)
                    } : nil
                )
                    .frame(maxWidth: usesCompactHeightLayout ? Layout.compactPanelMaxWidth : .infinity)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if liveSharing.isVisible {
                liveSharingPill
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !usesCompactHeightLayout, recorder.lastErrorMessage != nil {
                gpsPill
            }
        }
        .animation(reduceMotion ? nil : Motion.springSnappy, value: liveSharing.status)
        .animation(reduceMotion ? nil : Motion.springSnappy, value: liveSharing.riders.count)
        .animation(reduceMotion ? nil : Motion.spring, value: navigation.state)
        .padding(.horizontal, Spacing.screenH)
        .padding(.top, Spacing.sm)
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.selection()
                handleClose()
            } label: {
                Image(systemName: "xmark")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(MLPressableButtonStyle())
            .accessibilityLabel("Close recorder")

            Spacer()

            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(statusColor)
                    .frame(width: Spacing.xs, height: Spacing.xs)
                Text(statusTitle)
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextPrimary)
            }
            .lineLimit(1)
            .padding(.horizontal, Spacing.md)
            .frame(height: Spacing.xl + Spacing.xxs)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var gpsPill: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.mlWarning)
            Text(recorder.lastErrorMessage ?? "Location needs attention")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 40)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var liveSharingPill: some View {
        HStack(spacing: Spacing.xs) {
            Group {
                switch liveSharing.status {
                case .starting, .stopping:
                    ProgressView().tint(.mlAccent)
                case .sharing:
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.mlSuccess)
                case .failed:
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(Color.mlWarning)
                case .inactive, .unavailable, .stopped:
                    Image(systemName: "location.slash.fill")
                        .foregroundStyle(Color.mlTextTertiary)
                }
            }
            .frame(width: Spacing.md, height: Spacing.md)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(liveSharingTitle)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextPrimary)
                    .lineLimit(1)
                if let detail = liveSharingDetail {
                    Text(detail)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.xs)

            if case .failed = liveSharing.status {
                Button("Retry") {
                    Haptics.selection()
                    Task {
                        await liveSharing.start()
                        if let point = recorder.points.last {
                            await liveSharing.offer(point)
                        }
                    }
                }
                .font(MLFont.caption)
                .foregroundStyle(Color.mlAccent)
                .mlHitTarget()
                .buttonStyle(MLPressableButtonStyle())
            }

            if liveSharing.canStopSharing {
                Button {
                    Haptics.selection()
                    Task { await liveSharing.stop() }
                } label: {
                    Image(systemName: "xmark")
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlTextSecondary)
                        .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                }
                .buttonStyle(MLPressableButtonStyle())
                .accessibilityLabel("Stop sharing live position")
            }
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.xxs)
        .frame(minHeight: Spacing.xxl)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.mlTextPrimary.opacity(0.12), lineWidth: Layout.hairline))
    }

    private var liveSharingTitle: String {
        switch liveSharing.status {
        case .inactive, .starting:
            "Starting group sharing"
        case .sharing:
            "Sharing with \(groupRideContext?.title ?? "group")"
        case .failed:
            "Your sharing is offline"
        case .stopping:
            "Stopping group sharing"
        case .stopped:
            "Group map · You are private"
        case .unavailable:
            "Group map · You are private"
        }
    }

    private var liveSharingDetail: String? {
        if case .failed(let message) = liveSharing.status {
            return message
        }
        switch liveSharing.riderMapStatus {
        case .unavailable:
            return nil
        case .loading:
            return "Looking for riders"
        case .offline:
            return liveSharing.riders.isEmpty ? "Group map offline" : "Showing last fresh positions"
        case .live:
            let count = liveSharing.riders.count
            return count == 0 ? "No other riders live yet" : "\(count) other rider\(count == 1 ? "" : "s") live"
        }
    }

    private var controlPanel: some View {
        VStack(spacing: Spacing.sm) {
            if !showsTurnByTurnBanner, let followSnapshot {
                compactRouteGuidance(followSnapshot)
            }

            rideHUD
                .overlay(alignment: .topTrailing) {
                    if recorder.points.last != nil {
                        cameraControls
                            .offset(
                                x: -Spacing.sm,
                                y: -(Layout.minTouchTarget / 2)
                            )
                    }
                }
            if showsRideActions {
                actionButtons
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Motion.spring, value: showsRideActions)
        .padding(.horizontal, Spacing.screenH)
        .padding(.bottom, Spacing.sm)
        .frame(maxWidth: usesCompactHeightLayout ? Layout.liveCockpitMaxWidth : .infinity)
    }

    private var usesCompactHeightLayout: Bool {
        verticalSizeClass == .compact
    }

    private var controlPanelAlignment: Alignment {
        usesCompactHeightLayout ? .bottomTrailing : .bottom
    }

    private var showsRideActions: Bool {
        LiveRideCockpitPolicy.showsActions(
            status: recorder.status,
            speedMetersPerSecond: recorder.currentSpeedMetersPerSecond
        )
    }

    private func handleClose() {
        guard LiveRideCockpitPolicy.requiresEndRideDecision(
            status: recorder.status,
            pointCount: recorder.pointCount
        ) else {
            if recorder.status != .finished {
                recorder.discard()
            }
            dismiss()
            return
        }
        showingEndRideOptions = true
    }

    private func finishRide() {
        Haptics.success()
        Task {
            await liveSharing.endSession()
            recoveredFinishedRide = false
            finishedRide = await recorder.finish()
        }
    }

    private func discardActiveRide() {
        Haptics.warning()
        Task {
            await liveSharing.endSession()
            recorder.discard()
            dismiss()
        }
    }

    private var rideHUD: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            cockpitMetric(
                label: "Speed",
                value: speedText(recorder.currentSpeedMetersPerSecond),
                detail: "km/h",
                emphasis: true
            )

            cockpitDivider

            cockpitMetric(
                label: navigation.snapshot == nil ? "Time" : "Arrival",
                value: navigation.snapshot.map { arrivalTimeText($0.remainingTravelTime) }
                    ?? formattedDuration(recorder.elapsed),
                detail: navigation.snapshot == nil ? "elapsed" : navigation.snapshot?.etaText ?? ""
            )

            cockpitDivider

            cockpitMetric(
                label: navigation.snapshot == nil ? "Ride" : "Left",
                value: navigation.snapshot?.remainingDistanceText
                    ?? String(format: "%.2f", recorder.distanceKm),
                detail: navigation.snapshot == nil ? "km" : "remaining"
            )
        }
        .padding(Spacing.md)
        .background(Color.mlSurface.opacity(0.9), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlTextPrimary.opacity(0.12), lineWidth: Layout.hairline)
        )
        .shadow(color: .black.opacity(0.24), radius: Spacing.md, y: Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cockpitAccessibilityLabel)
    }

    private func cockpitMetric(label: String, value: String, detail: String, emphasis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label).mlKicker()
            Text(value)
                .font(emphasis ? MLFont.displayXL : MLFont.displaySmall)
                .foregroundStyle(Color.mlTextPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
            Text(detail)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cockpitDivider: some View {
        Rectangle()
            .fill(Color.mlHairline)
            .frame(width: Layout.hairline, height: Spacing.xl)
    }

    private var cockpitAccessibilityLabel: String {
        let speed = "Current speed \(speedText(recorder.currentSpeedMetersPerSecond)) kilometres per hour"
        guard let snapshot = navigation.snapshot else {
            return "\(speed), elapsed \(formattedDuration(recorder.elapsed)), distance \(String(format: "%.2f", recorder.distanceKm)) kilometres"
        }
        return "\(speed), arrival \(arrivalTimeText(snapshot.remainingTravelTime)), \(snapshot.remainingDistanceText) remaining"
    }

    private var followSnapshot: RouteFollowSnapshot? {
        guard let plannedRoute else { return nil }
        return routeFollowAnalyzer.snapshot(
            route: plannedRoute,
            recordedPoints: recorder.points,
            distanceMeters: recorder.distanceMeters
        )
    }

    private var showsTurnByTurnBanner: Bool {
        guard plannedRoute != nil else { return false }
        switch navigation.state {
        case .loading, .navigating, .rerouting, .unavailable, .arrived:
            return true
        case .inactive:
            return false
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch recorder.status {
        case .permissionDenied:
            PrimaryButton(title: "Open Location Settings", systemImage: "gear") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        case .idle:
            PrimaryButton(
                title: plannedRoute == nil ? "Start Recording" : "Start & Navigate",
                systemImage: "location.fill"
            ) {
                recorder.start()
            }
        case .recording, .paused:
            HStack(spacing: Spacing.md) {
                SecondaryButton(title: recorder.isPaused ? "Resume" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill") {
                    recorder.isPaused ? recorder.resume() : recorder.pause()
                }
                .background(.ultraThinMaterial, in: Capsule())
                PrimaryButton(title: "Finish", systemImage: "flag.checkered") {
                    showingFinishConfirmation = true
                }
            }
        case .finished:
            PrimaryButton(title: "Done", systemImage: "checkmark") {
                Task {
                    await liveSharing.endSession()
                    dismiss()
                }
            }
        }
    }

    private var statusTitle: String {
        switch recorder.status {
        case .idle: plannedRoute == nil ? "Starting Recorder" : "Preparing Navigation"
        case .recording: activeOfflineMapArea == nil ? "Recording" : "Recording · Offline"
        case .paused: "Paused"
        case .permissionDenied: "Permission Needed"
        case .finished: "Finished"
        }
    }

    private var statusColor: Color {
        switch recorder.status {
        case .recording: .mlAccent
        case .paused, .idle: .mlWarning
        case .permissionDenied: .mlDanger
        case .finished: .mlSuccess
        }
    }

    private func compactRouteGuidance(_ snapshot: RouteFollowSnapshot) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: snapshot.guidanceSymbol)
                .font(MLFont.title2)
                .foregroundStyle(routeStatusColor(snapshot))
                .frame(width: Spacing.xl + Spacing.xxs, height: Spacing.xl + Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(snapshot.guidanceTitle)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                    .lineLimit(1)
                Text("\(snapshot.guidanceDetail)  ·  \(snapshot.remainingText) left")
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            Text(snapshot.onRouteText)
                .font(MLFont.monoSmall)
                .foregroundStyle(routeStatusColor(snapshot))
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: Spacing.xxl + Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(routeStatusColor(snapshot).opacity(0.35), lineWidth: Layout.hairline)
        )
        .shadow(color: .black.opacity(0.2), radius: Spacing.sm, y: Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Route guidance")
        .accessibilityValue("\(snapshot.guidanceTitle), \(snapshot.guidanceDetail), \(snapshot.remainingText) remaining")
    }

    private func routeStatusColor(_ snapshot: RouteFollowSnapshot) -> Color {
        switch snapshot.status {
        case "On route": .mlSuccess
        case "Near route", "Waiting for GPS": .mlWarning
        default: .mlDanger
        }
    }

    private func speedText(_ metersPerSecond: Double) -> String {
        String(format: "%.0f", metersPerSecond * 3.6)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func arrivalTimeText(_ remainingTravelTime: TimeInterval) -> String {
        Date.now
            .addingTimeInterval(max(remainingTravelTime, 0))
            .formatted(date: .omitted, time: .shortened)
    }

    private func activateDownloadedMap(from areas: [OfflineMapArea], near coordinate: Coordinate?) {
        guard activeOfflineMapArea == nil else { return }
        if let coordinate,
           let area = areas.first(where: { $0.bounds.contains(coordinate) }) {
            activeOfflineMapArea = area
            return
        }
        guard let plannedRoute else { return }
        activeOfflineMapArea = areas.max { first, second in
            offlineCoverageScore(first, route: plannedRoute.route)
                < offlineCoverageScore(second, route: plannedRoute.route)
        }.flatMap { area in
            let sampledCount = offlineRouteSampleCount(plannedRoute.route)
            let coveredCount = offlineCoverageScore(area, route: plannedRoute.route)
            return sampledCount > 0 && Double(coveredCount) / Double(sampledCount) >= 0.8
                ? area
                : nil
        }
    }

    private func offlineCoverageScore(_ area: OfflineMapArea, route: [Coordinate]) -> Int {
        guard !route.isEmpty else { return 0 }
        let stride = max(route.count / 40, 1)
        return Swift.stride(from: 0, to: route.count, by: stride)
            .reduce(0) { score, index in
                score + (area.bounds.contains(route[index]) ? 1 : 0)
            }
    }

    private func offlineRouteSampleCount(_ route: [Coordinate]) -> Int {
        guard !route.isEmpty else { return 0 }
        let stride = max(route.count / 40, 1)
        return (route.count + stride - 1) / stride
    }
}

private extension TurnByTurnSessionState {
    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

enum LiveRideCockpitPolicy {
    static func showsActions(status: RecordingStatus, speedMetersPerSecond: Double) -> Bool {
        status != .recording || speedMetersPerSecond * 3.6 < 8
    }

    static func requiresEndRideDecision(status: RecordingStatus, pointCount: Int) -> Bool {
        pointCount > 0 && (status == .recording || status == .paused)
    }
}

private struct RecordingFinishedSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let result: RecordedRideResult
    let session: AuthSession
    let plannedRoute: PlannedRoute?
    @ObservedObject var uploadQueue: PendingRideUploadCoordinator
    let isRecovered: Bool
    let onSecured: () async -> Void
    let onQueued: () -> Void
    let onDiscard: () async -> Void
    let onDone: () -> Void

    @State private var title: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDiscardConfirmation = false

    init(
        result: RecordedRideResult,
        session: AuthSession,
        plannedRoute: PlannedRoute? = nil,
        uploadQueue: PendingRideUploadCoordinator,
        isRecovered: Bool = false,
        onSecured: @escaping () async -> Void,
        onQueued: @escaping () -> Void,
        onDiscard: @escaping () async -> Void,
        onDone: @escaping () -> Void
    ) {
        self.result = result
        self.session = session
        self.plannedRoute = plannedRoute
        self.uploadQueue = uploadQueue
        self.isRecovered = isRecovered
        self.onSecured = onSecured
        self.onQueued = onQueued
        self.onDiscard = onDiscard
        self.onDone = onDone
        _title = State(initialValue: Self.defaultTitle(for: result.startedAt))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Ride recorded").mlKicker()
                    Text("Save to Journal")
                        .font(MLFont.display)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text(isRecovered
                        ? "This completed ride was recovered from your device. Save it now to finish syncing it to Memory Lanes."
                        : "Your GPX backup is ready. Save it now to sync this ride across Memory Lanes.")
                        .font(MLFont.body)
                        .foregroundStyle(Color.mlTextSecondary)
                    if let plannedRoute {
                        Label(plannedRoute.title, systemImage: "map.fill")
                            .font(MLFont.callout)
                            .foregroundStyle(Color.mlAccent)
                            .lineLimit(1)
                    }
                }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Ride title").mlKicker()
                TextField("Recorded ride", text: $title)
                    .font(MLFont.body)
                    .foregroundStyle(Color.mlTextPrimary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .frame(minHeight: 52)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                    )
                    .disabled(isSaving)
            }

            LazyVGrid(columns: metricColumns, spacing: Spacing.md) {
                StatCard(label: "Distance", value: String(format: "%.2f", result.distanceMeters / 1000), unit: "km", systemImage: "map")
                StatCard(label: "Time", value: duration(result.durationSeconds), systemImage: "clock")
                StatCard(label: "Elevation", value: String(format: "%.0f", result.elevationGainMeters), unit: "m", systemImage: "mountain.2.fill")
                StatCard(label: "Points", value: "\(result.points.count)", systemImage: "location.fill")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlDanger)
                    .padding(Spacing.md)
                    .background(Color.mlDanger.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }

            PrimaryButton(title: "Save to Journal", systemImage: "tray.and.arrow.down.fill", isLoading: isSaving) {
                Task { await save() }
            }
            .disabled(!canSave)

            SecondaryButton(title: "Keep for Later", systemImage: "clock") {
                Task { await keepForLater() }
            }
            .disabled(isSaving)

                Button(role: .destructive) {
                    Haptics.warning()
                    showingDiscardConfirmation = true
                } label: {
                    Label("Discard Ride", systemImage: "trash")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlDanger)
                        .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                }
                .buttonStyle(MLPressableButtonStyle())
                .disabled(isSaving)
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mlBackground)
        .interactiveDismissDisabled()
        .confirmationDialog(
            isRecovered ? "Discard this recovered ride?" : "Discard this ride?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Ride", role: .destructive) {
                Task {
                    await onDiscard()
                    onDone()
                }
            }
            Button("Keep Ride", role: .cancel) {}
        } message: {
            Text("This permanently removes the pending ride from this device. It cannot be recovered later.")
        }
    }

    private var cleanTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var metricColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var canSave: Bool {
        !cleanTitle.isEmpty && !isSaving
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        do {
            let outcome = try await uploadQueue.submit(
                title: cleanTitle,
                result: result,
                plannedRouteID: plannedRoute?.id,
                userID: session.userID
            )
            await onSecured()
            if outcome == .queued {
                Haptics.warning()
                onQueued()
            } else {
                Haptics.success()
            }
            onDone()
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func keepForLater() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        do {
            try await uploadQueue.keepForLater(
                title: cleanTitle,
                result: result,
                plannedRouteID: plannedRoute?.id,
                userID: session.userID
            )
            await onSecured()
            Haptics.success()
            onQueued()
            onDone()
        } catch {
            Haptics.error()
            errorMessage = "This ride is still protected by recovery, but it could not be added to the sync queue. Try again before leaving."
        }
        isSaving = false
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Ride \(formatter.string(from: date))"
    }
}

#Preview {
    RecordingView(
        session: AuthSession(accessToken: "", refreshToken: "", expiresAt: Date().addingTimeInterval(3600), userID: UUID(), email: "preview@example.com"),
        plannedRoute: nil,
        accessToken: { "" },
        uploadQueue: PendingRideUploadCoordinator(monitorsNetwork: false)
    )
        .preferredColorScheme(.dark)
}
