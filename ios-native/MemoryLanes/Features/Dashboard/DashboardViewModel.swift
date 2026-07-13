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
        do {
            let rides = try await rideService.fetchRides()
            state = rides.isEmpty ? .empty : .loaded(rides)
        } catch is CancellationError {
            // View disappeared mid-load; leave state as-is.
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        // Same path as load, but doesn't flash the skeleton if we already
        // have content — the pull-to-refresh spinner covers the wait.
        do {
            let rides = try await rideService.fetchRides()
            state = rides.isEmpty ? .empty : .loaded(rides)
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
