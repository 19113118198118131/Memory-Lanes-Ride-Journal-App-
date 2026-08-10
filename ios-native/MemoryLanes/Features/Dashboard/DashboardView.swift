import SwiftUI

// MARK: - DashboardView
//
// The ride list / home screen, assembled entirely from library components. A
// proud hero metric up top, primary actions, then the ride list — each list
// state (loading / empty / error / populated) is handled explicitly.

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    @ObservedObject var uploadQueue: PendingRideUploadCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let refreshTrigger: UUID
    let onSelectRide: (Ride) -> Void
    let onStartRide: () -> Void
    let onImportRide: () -> Void
    let onShowStats: () -> Void

    init(
        viewModel: DashboardViewModel,
        uploadQueue: PendingRideUploadCoordinator,
        refreshTrigger: UUID = UUID(),
        onSelectRide: @escaping (Ride) -> Void = { _ in },
        onStartRide: @escaping () -> Void = {},
        onImportRide: @escaping () -> Void = {},
        onShowStats: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.uploadQueue = uploadQueue
        self.refreshTrigger = refreshTrigger
        self.onSelectRide = onSelectRide
        self.onStartRide = onStartRide
        self.onImportRide = onImportRide
        self.onShowStats = onShowStats
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                header
                heroMetrics.mlStaggeredReveal(index: 3)
                startTile.mlStaggeredReveal(index: 4)
                if uploadQueue.pendingCount > 0 {
                    pendingSyncNotice
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .mlStaggeredReveal(index: 5)
                }

                SectionHeader(title: "Recent Rides",
                              actionTitle: viewModel.rides.isEmpty ? nil : "Stats",
                              action: viewModel.rides.isEmpty ? nil : onShowStats)
                    .mlStaggeredReveal(index: 6)

                content
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
            .mlTabBarContentClearance()
        }
        .background(Color.mlBackground)
        .refreshable { await viewModel.refresh() }
        .task(id: refreshTrigger) { await viewModel.load() }
        .animation(reduceMotion ? nil : Motion.springSnappy, value: uploadQueue.pendingCount)
    }

    // MARK: Header

    private var header: some View {
        ScreenIntro(kicker: "Ride Journal", title: "Memory Lanes")
        .padding(.top, Spacing.xs)
    }

    // MARK: Hero metrics

    private var heroMetrics: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Spacing.md) { heroMetricCards }
            } else {
                HStack(spacing: Spacing.md) { heroMetricCards }
            }
        }
        .redacted(reason: isLoading ? .placeholder : [])
    }

    @ViewBuilder
    private var heroMetricCards: some View {
            StatCard(
                label: "This Week",
                value: String(format: "%.0f", viewModel.weeklyDistanceKm),
                unit: "km",
                trend: .neutral("\(viewModel.weeklyRideCount) rides"),
                systemImage: "calendar"
            )
            StatCard(
                label: "Best Flow",
                value: viewModel.bestFlow.map(String.init) ?? "—",
                systemImage: "waveform.path.ecg"
            )
    }

    // MARK: Start tile

    private var startTile: some View {
        VStack(spacing: Spacing.md) {
            PrimaryButton(title: "Start Ride", systemImage: "play.fill") {
                onStartRide()
            }
            SecondaryButton(title: "Import GPX", systemImage: "square.and.arrow.down") {
                onImportRide()
            }
        }
    }

    private var pendingSyncNotice: some View {
        Button {
            Haptics.selection()
            Task { await uploadQueue.sync() }
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.mlAccent.opacity(0.14))
                        .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                    if uploadQueue.phase == .syncing {
                        ProgressView()
                            .tint(Color.mlAccent)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(MLFont.headline)
                            .foregroundStyle(Color.mlAccent)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(syncTitle)
                        .font(MLFont.headline)
                        .foregroundStyle(Color.mlTextPrimary)
                    Text(syncDetail)
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Spacing.xs)

                if uploadQueue.phase != .syncing {
                    Image(systemName: "arrow.clockwise")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlAccent)
                        .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                }
            }
            .padding(Spacing.md)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.mlAccent.opacity(0.18), lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(MLPressableButtonStyle())
        .disabled(uploadQueue.phase == .syncing)
        .accessibilityLabel("\(syncTitle). \(syncDetail)")
        .accessibilityHint(uploadQueue.phase == .syncing ? "" : "Retries the upload")
    }

    private var syncTitle: String {
        let noun = uploadQueue.pendingCount == 1 ? "ride" : "rides"
        if uploadQueue.phase == .syncing {
            return "Syncing \(uploadQueue.pendingCount) \(noun)"
        }
        return "\(uploadQueue.pendingCount) \(noun) safe on this iPhone"
    }

    private var syncDetail: String {
        uploadQueue.phase == .syncing
            ? "Uploading securely to your journal"
            : "Waiting to sync. Tap to try again."
    }

    // MARK: List content — every state handled

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            VStack(spacing: Spacing.md) {
                RideCardSkeleton()
                RideCardSkeleton()
            }
        case .loaded(let rides):
            LazyVStack(spacing: Spacing.md) {
                ForEach(Array(rides.enumerated()), id: \.element.id) { index, ride in
                    RideCard(ride: ride) { onSelectRide(ride) }
                        .mlStaggeredReveal(index: index)
                }
            }
        case .empty:
            EmptyState(
                systemImage: "map",
                title: "No rides yet",
                message: "Upload a GPX track or start a live ride — your first journal entry will appear here.",
                actionTitle: "Start Your First Ride"
            ) { onStartRide() }
            .padding(.top, Spacing.xl)
        case .failed(let message):
            EmptyState(
                systemImage: "wifi.exclamationmark",
                title: "Couldn’t load rides",
                message: message,
                actionTitle: "Try Again"
            ) {
                Task { await viewModel.load() }
            }
            .padding(.top, Spacing.xl)
        }
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state { return true }
        return false
    }
}

// MARK: - Previews

#Preview("Dashboard — populated") {
    DashboardView(
        viewModel: DashboardViewModel(rideService: PreviewRideService()),
        uploadQueue: PendingRideUploadCoordinator(monitorsNetwork: false)
    )
        .preferredColorScheme(.dark)
}

#Preview("Dashboard — empty") {
    DashboardView(viewModel: DashboardViewModel(
        rideService: PreviewRideService(rides: [])
    ), uploadQueue: PendingRideUploadCoordinator(monitorsNetwork: false))
    .preferredColorScheme(.dark)
}

#Preview("Dashboard — error") {
    DashboardView(viewModel: DashboardViewModel(
        rideService: PreviewRideService(failure: .notImplemented)
    ), uploadQueue: PendingRideUploadCoordinator(monitorsNetwork: false))
    .preferredColorScheme(.dark)
}
