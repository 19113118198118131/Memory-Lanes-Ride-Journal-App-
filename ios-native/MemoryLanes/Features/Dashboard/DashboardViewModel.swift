import Foundation
import Observation

// MARK: - DashboardViewModel
//
// One ViewModel per screen (brief rule). All loading / derivation lives here so
// the View is pure layout. `@Observable` (iOS 17) drives SwiftUI updates; the
// class is `@MainActor` because it publishes UI state.

@MainActor
@Observable
final class DashboardViewModel {
    enum LoadState {
        case loading
        case loaded([Ride])
        case empty
        case failed(String)
    }

    private(set) var state: LoadState = .loading

    /// Injected so the screen is testable and the network layer is swappable.
    private let rideService: RideServing
    private var hydrationTask: Task<Void, Never>?

    init(rideService: RideServing) {
        self.rideService = rideService
    }

    /// Rides currently available (empty while loading / on error).
    var rides: [Ride] {
        if case .loaded(let rides) = state { return rides }
        return []
    }

    // MARK: Derived hero metrics

    var weeklyDistanceKm: Double {
        let weekAgo = Date().addingTimeInterval(-86_400 * 7)
        return rides
            .filter { $0.date >= weekAgo }
            .reduce(0) { $0 + $1.distanceMeters } / 1000
    }

    var weeklyRideCount: Int {
        let weekAgo = Date().addingTimeInterval(-86_400 * 7)
        return rides.filter { $0.date >= weekAgo }.count
    }

    var bestFlow: Int? {
        rides.compactMap(\.flowScore).max()
    }

    var latestRide: Ride? {
        rides.max(by: { $0.date < $1.date })
    }

    // MARK: Loading

    func load() async {
        state = .loading
        let cached = await rideService.cachedRides()
        if !cached.isEmpty {
            state = .loaded(cached)
            startPreviewHydration()
        }
        await fetchAndHydrate(preserveCurrentOnFailure: !cached.isEmpty)
    }

    func refresh() async {
        // Same path as load, but doesn't flash the skeleton if we already
        // have content — the pull-to-refresh spinner covers the wait.
        await fetchAndHydrate(preserveCurrentOnFailure: !rides.isEmpty)
    }

    private func fetchAndHydrate(preserveCurrentOnFailure: Bool) async {
        do {
            let rides = try await rideService.fetchRides()
            state = rides.isEmpty ? .empty : .loaded(rides)
            startPreviewHydration()
        } catch is CancellationError {
            // View disappeared mid-load; leave state as-is.
        } catch {
            if !preserveCurrentOnFailure {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Loads route thumbnails in the background so the list renders instantly
    /// and fills in as each preview arrives. Not awaited by `refresh()`, so
    /// pull-to-refresh completes as soon as the list itself is ready.
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
