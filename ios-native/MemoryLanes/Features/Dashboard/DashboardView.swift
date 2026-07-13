import SwiftUI

// MARK: - DashboardView
//
// The ride list / home screen, assembled entirely from library components. A
// proud hero metric up top, primary actions, then the ride list — each list
// state (loading / empty / error / populated) is handled explicitly.

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    @State private var toast: Toast?
    var onSelectRide: (Ride) -> Void = { _ in }
    var onStartRide: () -> Void = {}

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                header
                heroMetrics
                startTile

                SectionHeader(title: "Recent Rides",
                              actionTitle: viewModel.rides.isEmpty ? nil : "Stats",
                              action: viewModel.rides.isEmpty ? nil : {})

                content
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .mlToast($toast)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Ride Journal").mlKicker()
            Text("Memory Lanes")
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
        }
        .padding(.top, Spacing.xs)
    }

    // MARK: Hero metrics

    private var heroMetrics: some View {
        HStack(spacing: Spacing.md) {
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
        .redacted(reason: isLoading ? .placeholder : [])
    }

    // MARK: Start tile

    private var startTile: some View {
        PrimaryButton(title: "Start Ride", systemImage: "play.fill") {
            onStartRide()
        }
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
                ForEach(rides) { ride in
                    RideCard(ride: ride) { onSelectRide(ride) }
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
    DashboardView(viewModel: DashboardViewModel(rideService: PreviewRideService()))
        .preferredColorScheme(.dark)
}

#Preview("Dashboard — empty") {
    DashboardView(viewModel: DashboardViewModel(
        rideService: PreviewRideService(rides: [])
    ))
    .preferredColorScheme(.dark)
}

#Preview("Dashboard — error") {
    DashboardView(viewModel: DashboardViewModel(
        rideService: PreviewRideService(failure: .notImplemented)
    ))
    .preferredColorScheme(.dark)
}
