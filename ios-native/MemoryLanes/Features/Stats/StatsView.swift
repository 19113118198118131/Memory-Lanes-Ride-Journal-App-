import SwiftUI
import MapKit

// MARK: - StatsView
//
// Native lifetime stats sourced from Supabase rides. Mirrors the web stats page:
// totals, monthly distance, personal bests, and a glanceable ridden-routes map.

struct StatsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: StatsViewModel
    let refreshTrigger: UUID
    let onSelectRide: (Ride) -> Void

    init(
        viewModel: StatsViewModel,
        refreshTrigger: UUID = UUID(),
        onSelectRide: @escaping (Ride) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.refreshTrigger = refreshTrigger
        self.onSelectRide = onSelectRide
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                header
                content
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task(id: refreshTrigger) { await viewModel.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Lifetime stats").mlKicker()
            Text("Every ride adds up")
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
            Text("Distance, riding time, standout rides, and everywhere you have ridden.")
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            loadingContent
        case .loaded:
            totals
            if RiderCraftFeature.isResearchPreviewEnabled {
                RiderCraftProgressView(progress: viewModel.riderCraftProgress)
            }
            monthlyCard
            personalBests
            riddenMap
        case .empty:
            EmptyState(
                systemImage: "chart.bar",
                title: "No stats yet",
                message: "Record or import a ride, and your lifetime stats will appear here."
            )
            .padding(.top, Spacing.xl)
        case .failed(let message):
            EmptyState(
                systemImage: "wifi.exclamationmark",
                title: "Couldn’t load stats",
                message: message,
                actionTitle: "Try Again"
            ) {
                Task { await viewModel.load() }
            }
            .padding(.top, Spacing.xl)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: Spacing.md) {
            LazyVGrid(columns: metricColumns, spacing: Spacing.md) {
                SkeletonBar(height: 112, radius: Radius.card).mlShimmer()
                SkeletonBar(height: 112, radius: Radius.card).mlShimmer()
                SkeletonBar(height: 112, radius: Radius.card).mlShimmer()
                SkeletonBar(height: 112, radius: Radius.card).mlShimmer()
            }
            SkeletonBar(height: 220, radius: Radius.card).mlShimmer()
            SkeletonBar(height: 180, radius: Radius.card).mlShimmer()
        }
    }

    private var totals: some View {
        LazyVGrid(columns: metricColumns, spacing: Spacing.md) {
            StatCard(label: "Rides", value: "\(viewModel.rides.count)", systemImage: "helmet")
            StatCard(label: "Distance", value: String(format: "%.0f", viewModel.totalDistanceKm), unit: "km", systemImage: "road.lanes")
            biggestClimbCard
            StatCard(label: "Time Riding", value: formattedDuration(viewModel.totalDuration), systemImage: "clock.fill")
        }
    }

    @ViewBuilder
    private var biggestClimbCard: some View {
        if let ride = viewModel.highestRide {
            Button {
                Haptics.selection()
                onSelectRide(ride)
            } label: {
                StatCard(
                    label: "Biggest Climb",
                    value: ride.elevationFormatted,
                    unit: "m",
                    systemImage: "mountain.2.fill"
                )
            }
            .buttonStyle(MLPressableButtonStyle(scale: 0.98))
        }
    }

    private var metricColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var monthlyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Monthly Distance")
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                ForEach(viewModel.monthlyBars) { bar in
                    VStack(spacing: Spacing.xs) {
                        Text(bar.distanceKm > 0 ? String(format: "%.0f", bar.distanceKm) : "0")
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextSecondary)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.mlAccent.gradient)
                            .frame(height: max(18, CGFloat(bar.heightRatio) * 118))
                            .opacity(bar.distanceKm > 0 ? 1 : 0.22)
                        Text(bar.label)
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(bar.label): \(String(format: "%.0f", bar.distanceKm)) kilometres, \(bar.rideCount) rides")
                }
            }
            .frame(height: 170)
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private var personalBests: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Personal Bests")
            if let ride = viewModel.bestFlowRide, let flow = ride.flowScore {
                bestRow(label: "Best Flow", value: "\(flow)", ride: ride, symbol: "trophy.fill")
            }
            if let ride = viewModel.longestRide {
                bestRow(label: "Longest Ride", value: "\(ride.distanceFormatted) km", ride: ride, symbol: "arrow.up.right.circle.fill")
            }
            if let ride = viewModel.mostCornersRide,
               let corners = ride.riderCraftSummary?.cornerCount {
                bestRow(label: "Most Corners", value: "\(corners)", ride: ride, symbol: "road.lanes.curved.right")
            }
            if let ride = viewModel.longestDurationRide {
                bestRow(label: "Longest Time Out", value: formattedDuration(ride.durationSeconds), ride: ride, symbol: "clock.fill")
            }
        }
    }

    private var riddenMap: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Everywhere You've Ridden")
            if viewModel.routePreviews.isEmpty {
                EmptyState(
                    systemImage: "map",
                    title: "No route previews yet",
                    message: "Saved GPX-backed rides will draw here."
                )
            } else {
                StatsRoutesMap(routes: viewModel.routePreviews)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private func bestRow(label: String, value: String, ride: Ride, symbol: String) -> some View {
        Button {
            Haptics.selection()
            onSelectRide(ride)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.mlAccent)
                    .frame(width: 42, height: 42)
                    .background(Color.mlAccent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(label).mlKicker()
                    Text(ride.title)
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(value)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
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

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

private struct StatsRoutesMap: View {
    let routes: [[Coordinate]]

    private var allCoordinates: [Coordinate] {
        routes.flatMap { $0 }
    }

    var body: some View {
        Map(initialPosition: .region(RouteGeometry.region(for: allCoordinates, paddingFactor: 1.55))) {
            ForEach(Array(routes.enumerated()), id: \.offset) { index, route in
                MapPolyline(coordinates: route.clCoordinates)
                    .stroke(
                        index == 0 ? Color.mlAccent : Color.mlAccent.opacity(0.42),
                        style: StrokeStyle(lineWidth: index == 0 ? 4 : 2.5, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .accessibilityLabel("Map of ridden routes")
    }
}

#Preview {
    NavigationStack {
        StatsView(viewModel: StatsViewModel(rideService: PreviewRideService()))
    }
    .preferredColorScheme(.dark)
}
