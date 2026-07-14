import Foundation
import Observation

@MainActor
@Observable
final class StatsViewModel {
    enum LoadState {
        case loading
        case loaded([Ride])
        case empty
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private let rideService: RideServing
    private var hydrationTask: Task<Void, Never>?

    init(rideService: RideServing) {
        self.rideService = rideService
    }

    var rides: [Ride] {
        if case .loaded(let rides) = state { return rides }
        return []
    }

    var totalDistanceKm: Double {
        rides.reduce(0) { $0 + $1.distanceMeters } / 1000
    }

    var totalDuration: TimeInterval {
        rides.reduce(0) { $0 + $1.durationSeconds }
    }

    var riderCraftProgress: RiderCraftProgress {
        RiderCraftProgressAnalyzer().analyze(rides: rides)
    }

    var bestFlowRide: Ride? {
        rides.compactMap { ride in
            ride.flowScore.map { (ride, $0) }
        }
        .max { $0.1 < $1.1 }?
        .0
    }

    var longestRide: Ride? {
        rides.max { $0.distanceMeters < $1.distanceMeters }
    }

    var highestRide: Ride? {
        rides.max { $0.elevationGainMeters < $1.elevationGainMeters }
    }

    var longestDurationRide: Ride? {
        rides.max { $0.durationSeconds < $1.durationSeconds }
    }

    var mostCornersRide: Ride? {
        rides
            .filter { $0.riderCraftSummary?.cornerCount != nil }
            .max {
                ($0.riderCraftSummary?.cornerCount ?? 0) < ($1.riderCraftSummary?.cornerCount ?? 0)
            }
    }

    var monthlyBars: [StatsMonthBar] {
        let calendar = Calendar.current
        let now = Date()
        let startMonths = (0..<6).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: calendar.startOfMonth(for: now))
        }

        let buckets = startMonths.map { monthStart -> StatsMonthBar in
            let next = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let monthRides = rides.filter { $0.date >= monthStart && $0.date < next }
            let km = monthRides.reduce(0) { $0 + $1.distanceMeters } / 1000
            return StatsMonthBar(
                id: monthStart,
                label: monthStart.formatted(.dateTime.month(.abbreviated)),
                rideCount: monthRides.count,
                distanceKm: km
            )
        }

        let maxKm = max(buckets.map(\.distanceKm).max() ?? 0, 1)
        return buckets.map { bar in
            var copy = bar
            copy.heightRatio = bar.distanceKm / maxKm
            return copy
        }
    }

    var routePreviews: [[Coordinate]] {
        rides.map(\.routePreview).filter { $0.count > 1 }
    }

    func load() async {
        state = .loading
        await refresh()
    }

    func refresh() async {
        do {
            let rides = try await rideService.fetchRides()
            state = rides.isEmpty ? .empty : .loaded(rides)
            startPreviewHydration()
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Route previews power the "everywhere you've ridden" map, hydrated in the
    /// background so the totals and charts render without waiting on GPX.
    private func startPreviewHydration() {
        guard case .loaded(let rides) = state else { return }
        let service = rideService
        hydrationTask?.cancel()
        hydrationTask = Task { [weak self] in
            await RidePreviewHydration.run(for: rides, using: service) { id, preview in
                self?.applyPreview(preview, to: id)
            }
        }
    }

    private func applyPreview(_ preview: [Coordinate], to id: UUID) {
        guard case .loaded(var rides) = state,
              let index = rides.firstIndex(where: { $0.id == id }) else { return }
        rides[index].routePreview = preview
        state = .loaded(rides)
    }
}

struct StatsMonthBar: Identifiable, Hashable {
    let id: Date
    let label: String
    let rideCount: Int
    let distanceKm: Double
    var heightRatio: Double = 0
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
