import SwiftUI

// MARK: - StatsView
//
// Native lifetime-stats screen. It reads from the same ride list that powers
// the dashboard today; later the service will provide the real user rides.

struct StatsView: View {
    private let rides = SampleData.rides

    private var totalDistanceKm: Double {
        rides.reduce(0) { $0 + $1.distanceMeters } / 1000
    }

    private var totalElevationM: Double {
        rides.reduce(0) { $0 + $1.elevationGainMeters }
    }

    private var totalDuration: TimeInterval {
        rides.reduce(0) { $0 + $1.durationSeconds }
    }

    private var bestFlowRide: Ride? {
        rides.max { ($0.flowScore ?? 0) < ($1.flowScore ?? 0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                header
                totals
                monthlyCard
                personalBests
                riddenMap
            }
            .padding(.vertical, Spacing.md)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Lifetime stats").mlKicker()
            Text("Every ride adds up")
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
            Text("Distance, elevation, riding time, personal bests, and everywhere you have ridden.")
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
        }
    }

    private var totals: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
            StatCard(label: "Rides", value: "\(rides.count)", systemImage: "helmet")
            StatCard(label: "Distance", value: String(format: "%.0f", totalDistanceKm), unit: "km", systemImage: "road.lanes")
            StatCard(label: "Elevation", value: String(format: "%.0f", totalElevationM), unit: "m", systemImage: "mountain.2.fill")
            StatCard(label: "Time Riding", value: formattedDuration(totalDuration), systemImage: "clock.fill")
        }
    }

    private var monthlyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Rides per Month")
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                ForEach(monthBars, id: \.label) { bar in
                    VStack(spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.mlAccent.gradient)
                            .frame(height: max(18, bar.height))
                        Text(bar.label)
                            .font(MLFont.caption)
                            .foregroundStyle(Color.mlTextTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150)
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
            bestRow(label: "Best Flow", value: "\(bestFlowRide?.flowScore ?? 0)", ride: bestFlowRide?.title ?? "No scored ride yet", symbol: "trophy.fill")
            bestRow(label: "Longest Ride", value: "\(longestRide.distanceFormatted) km", ride: longestRide.title, symbol: "arrow.up.right.circle.fill")
            bestRow(label: "Biggest Climb", value: "\(highestRide.elevationFormatted) m", ride: highestRide.title, symbol: "mountain.2.fill")
        }
    }

    private var riddenMap: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Everywhere You've Ridden")
            RouteThumbnail(route: SampleData.ridgeRoute)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.mlHairline, lineWidth: Layout.hairline)
        )
    }

    private var longestRide: Ride {
        rides.max { $0.distanceMeters < $1.distanceMeters } ?? SampleData.hero
    }

    private var highestRide: Ride {
        rides.max { $0.elevationGainMeters < $1.elevationGainMeters } ?? SampleData.hero
    }

    private var monthBars: [MonthBar] {
        [
            .init(label: "Feb", height: 34),
            .init(label: "Mar", height: 76),
            .init(label: "Apr", height: 52),
            .init(label: "May", height: 110),
            .init(label: "Jun", height: 88),
            .init(label: "Jul", height: 132)
        ]
    }

    private func bestRow(label: String, value: String, ride: String, symbol: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(Color.mlAccent)
                .frame(width: 42, height: 42)
                .background(Color.mlAccent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(label).mlKicker()
                Text(ride)
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
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

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }
}

private struct MonthBar {
    let label: String
    let height: CGFloat
}

#Preview {
    NavigationStack { StatsView() }
        .preferredColorScheme(.dark)
}
