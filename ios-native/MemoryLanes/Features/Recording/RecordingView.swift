import SwiftUI

// MARK: - RecordingView
//
// Native ride recording cockpit. This is intentionally local/demo-backed for now:
// the next step is replacing simulated telemetry with Core Location updates and
// writing completed rides through the service layer.

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var elapsed: TimeInterval = 0
    @State private var isPaused = false
    @State private var showingFinishConfirmation = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var distanceKm: Double {
        elapsed * 0.0062
    }

    private var averageSpeedKmh: Double {
        guard elapsed > 0 else { return 0 }
        return distanceKm / (elapsed / 3600)
    }

    private var currentSpeedKmh: Double {
        isPaused ? 0 : min(58, max(18, averageSpeedKmh + sin(elapsed / 12) * 6))
    }

    private var routePreview: [Coordinate] {
        let route = SampleData.ridgeRoute
        let progress = min(1, elapsed / 240)
        let visibleCount = max(2, min(route.count, Int(Double(route.count) * progress) + 2))
        return Array(route.prefix(visibleCount))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            controlPanel
        }
        .background(Color.mlBackground)
        .ignoresSafeArea(edges: .top)
        .onReceive(timer) { _ in
            guard !isPaused else { return }
            elapsed += 1
        }
        .alert("Finish ride?", isPresented: $showingFinishConfirmation) {
            Button("Keep Riding", role: .cancel) {}
            Button("Finish", role: .destructive) {
                Haptics.success()
                dismiss()
            }
        } message: {
            Text("This will end the current recording. Saving to your journal will be wired when live ride storage lands.")
        }
    }

    private var mapLayer: some View {
        MLMapView(route: routePreview, fadeColor: .mlBackground)
            .overlay(alignment: .top) {
                VStack(spacing: Spacing.sm) {
                    topBar
                    gpsPill
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.top, 58)
            }
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.selection()
                showingFinishConfirmation = true
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

            Text(isPaused ? "Paused" : "Recording")
                .font(MLFont.callout)
                .foregroundStyle(isPaused ? Color.mlWarning : Color.mlAccent)
                .padding(.horizontal, Spacing.md)
                .frame(height: 36)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var gpsPill: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(isPaused ? Color.mlWarning : Color.mlSuccess)
                .frame(width: 8, height: 8)
            Text(isPaused ? "GPS held while paused" : "GPS locked")
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextPrimary)
            Spacer()
            Text("\(routePreview.count) pts")
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
                Text("Live ride").mlKicker()
                Text(formattedDuration(elapsed))
                    .font(MLFont.displayXL)
                    .foregroundStyle(Color.mlTextPrimary)
                    .contentTransition(.numericText())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                liveMetric(label: "Distance", value: String(format: "%.2f", distanceKm), unit: "km", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                liveMetric(label: "Current", value: String(format: "%.0f", currentSpeedKmh), unit: "km/h", symbol: "speedometer")
                liveMetric(label: "Average", value: String(format: "%.0f", averageSpeedKmh), unit: "km/h", symbol: "gauge.with.dots.needle.67percent")
                liveMetric(label: "Elevation", value: String(format: "%.0f", distanceKm * 21), unit: "m", symbol: "mountain.2.fill")
            }

            HStack(spacing: Spacing.md) {
                SecondaryButton(title: isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill") {
                    isPaused.toggle()
                }
                PrimaryButton(title: "Finish", systemImage: "flag.checkered") {
                    showingFinishConfirmation = true
                }
            }
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

#Preview {
    RecordingView()
        .preferredColorScheme(.dark)
}
