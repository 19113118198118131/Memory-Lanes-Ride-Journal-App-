import SwiftUI
import UIKit

// MARK: - RecordingView
//
// Native ride recording cockpit backed by Core Location. It records real device
// points, persists an interrupted draft, and creates GPX text when finished.

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    let session: AuthSession
    let plannedRoute: PlannedRoute?
    let onSaved: (Ride) -> Void

    @StateObject private var recorder = LiveRideRecorder()
    @State private var showingFinishConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var finishedRide: RecordedRideResult?
    @State private var recoveredFinishedRide = false
    private let routeFollowAnalyzer = RouteFollowAnalyzer()

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            controlPanel
        }
        .background(Color.mlBackground)
        .ignoresSafeArea(edges: .top)
        .task {
            if let recovered = await recorder.prepareForPresentation() {
                recoveredFinishedRide = true
                finishedRide = recovered
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert("Finish ride?", isPresented: $showingFinishConfirmation) {
            Button("Keep Riding", role: .cancel) {}
            Button("Finish") {
                Haptics.success()
                Task {
                    recoveredFinishedRide = false
                    finishedRide = await recorder.finish()
                }
            }
        } message: {
            Text("Memory Lanes will stop recording, export a GPX backup, and let you save it to your journal.")
        }
        .alert("Discard ride?", isPresented: $showingDiscardConfirmation) {
            Button("Keep Riding", role: .cancel) {}
            Button("Discard", role: .destructive) {
                Haptics.warning()
                recorder.discard()
                dismiss()
            }
        } message: {
            Text("This deletes the active recording draft from this device.")
        }
        .sheet(item: $finishedRide) { result in
            RecordingFinishedSheet(
                result: result,
                session: session,
                plannedRoute: plannedRoute,
                isRecovered: recoveredFinishedRide,
                onSaved: { ride in
                    await recorder.markCompletedRideSaved(result)
                    onSaved(ride)
                }
            ) {
                dismiss()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var mapLayer: some View {
        Group {
            if recorder.routePreview.count > 1 {
                MLMapView(route: recorder.routePreview, fadeColor: .mlBackground, guideRoute: plannedRoute?.route ?? [])
            } else if let plannedRoute, plannedRoute.route.count > 1 {
                MLMapView(route: [], fadeColor: .mlBackground, guideRoute: plannedRoute.route)
            } else {
                MLMapView(route: SampleData.ridgeRoute, fadeColor: .mlBackground)
                    .overlay(Color.black.opacity(0.42))
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: Spacing.sm) {
                topBar
                gpsPill
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.xxl + Spacing.xs)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.selection()
                showingDiscardConfirmation = true
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

            Text(statusTitle)
                .font(MLFont.callout)
                .foregroundStyle(statusColor)
                .padding(.horizontal, Spacing.md)
                .frame(height: 36)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var gpsPill: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(recorder.lastErrorMessage ?? recorder.permissionSummary)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(recorder.pointCount) pts")
                .font(MLFont.monoSmall)
                .foregroundStyle(Color.mlTextSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 40)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(plannedRoute == nil ? "Live ride" : "Following route").mlKicker()
                Text(formattedDuration(recorder.elapsed))
                    .font(MLFont.displayXL)
                    .foregroundStyle(Color.mlTextPrimary)
                    .contentTransition(.numericText())
                if let plannedRoute {
                    Text(plannedRoute.title)
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                        .lineLimit(1)
                }
            }

            if let followSnapshot {
                followRouteCard(followSnapshot)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                liveMetric(label: "Distance", value: String(format: "%.2f", recorder.distanceKm), unit: "km", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                liveMetric(label: "Current", value: speedText(recorder.currentSpeedMetersPerSecond), unit: "km/h", symbol: "speedometer")
                liveMetric(label: "Average", value: speedText(recorder.averageSpeedMetersPerSecond), unit: "km/h", symbol: "gauge.with.dots.needle.67percent")
                liveMetric(label: "Elevation", value: String(format: "%.0f", recorder.elevationGainMeters), unit: "m", symbol: "mountain.2.fill")
            }

            actionButtons
        }
        .padding(Spacing.lg)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mlBackground, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.mlHairline)
                .frame(width: 42, height: 4)
                .padding(.top, Spacing.sm)
        }
    }

    private var followSnapshot: RouteFollowSnapshot? {
        guard let plannedRoute else { return nil }
        return routeFollowAnalyzer.snapshot(
            route: plannedRoute,
            recordedPoints: recorder.points,
            distanceMeters: recorder.distanceMeters
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch recorder.status {
        case .permissionDenied:
            PrimaryButton(title: "Try Again", systemImage: "location.fill") {
                recorder.start()
            }
        case .idle:
            PrimaryButton(title: "Start", systemImage: "location.fill") {
                recorder.start()
            }
        case .recording, .paused:
            HStack(spacing: Spacing.md) {
                SecondaryButton(title: recorder.isPaused ? "Resume" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill") {
                    recorder.isPaused ? recorder.resume() : recorder.pause()
                }
                PrimaryButton(title: "Finish", systemImage: "flag.checkered") {
                    showingFinishConfirmation = true
                }
            }
        case .finished:
            PrimaryButton(title: "Done", systemImage: "checkmark") {
                dismiss()
            }
        }
    }

    private var statusTitle: String {
        switch recorder.status {
        case .idle: "Starting"
        case .recording: "Recording"
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

    private func liveMetric(label: String, value: String, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: symbol)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlAccent)
                Text(label).mlKicker()
            }

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(MLFont.displaySmall)
                    .foregroundStyle(Color.mlTextPrimary)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func followRouteCard(_ snapshot: RouteFollowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Route guidance").mlKicker()
                    Text(snapshot.status)
                        .font(MLFont.headline)
                        .foregroundStyle(routeStatusColor(snapshot))
                }
                Spacer()
                Text(snapshot.onRouteText)
                    .font(MLFont.monoSmall)
                    .foregroundStyle(Color.mlTextPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(Color.mlSurfaceElevated, in: Capsule())
            }

            ProgressView(value: snapshot.progressPercent, total: 100)
                .tint(Color.mlAccent)
                .accessibilityLabel("Route progress")
                .accessibilityValue("\(Int(snapshot.progressPercent.rounded())) percent")

            HStack(spacing: Spacing.sm) {
                followMetric("Remaining", snapshot.remainingText, "flag.checkered")
                followMetric("Drift", snapshot.deviationText, "scope")
                followMetric("Progress", String(format: "%.0f%%", snapshot.progressPercent), "chart.line.uptrend.xyaxis")
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func followMetric(_ label: String, _ value: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Label(label, systemImage: systemImage)
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextSecondary)
                .lineLimit(1)
            Text(value)
                .font(MLFont.monoSmall)
                .foregroundStyle(Color.mlTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

private struct RecordingFinishedSheet: View {
    let result: RecordedRideResult
    let session: AuthSession
    let plannedRoute: PlannedRoute?
    let isRecovered: Bool
    let onSaved: (Ride) async -> Void
    let onDone: () -> Void

    @State private var title: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let importService = RideImportService()

    init(
        result: RecordedRideResult,
        session: AuthSession,
        plannedRoute: PlannedRoute? = nil,
        isRecovered: Bool = false,
        onSaved: @escaping (Ride) async -> Void,
        onDone: @escaping () -> Void
    ) {
        self.result = result
        self.session = session
        self.plannedRoute = plannedRoute
        self.isRecovered = isRecovered
        self.onSaved = onSaved
        self.onDone = onDone
        _title = State(initialValue: Self.defaultTitle(for: result.startedAt))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
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
                    .frame(height: 52)
                    .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                    )
                    .disabled(isSaving)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
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

            SecondaryButton(title: "Not Now", systemImage: "clock") {
                onDone()
            }
            .disabled(isSaving)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mlBackground)
    }

    private var cleanTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !cleanTitle.isEmpty && !isSaving
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        do {
            let saved = try await importService.saveRecordedRide(
                title: cleanTitle,
                result: result,
                plannedRouteID: plannedRoute?.id,
                session: session
            )
            Haptics.success()
            await onSaved(saved)
            onDone()
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
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
        onSaved: { _ in }
    )
        .preferredColorScheme(.dark)
}
