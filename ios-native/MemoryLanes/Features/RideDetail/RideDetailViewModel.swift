import Foundation
import Observation

// MARK: - RideDetailViewModel
//
// Owns the detail load for one ride and the section the rider is viewing. The
// parent `Ride` (already in hand from the list) is passed in so the hero map and
// headline stats render instantly while the deeper analysis streams in.

@MainActor
@Observable
final class RideDetailViewModel {
    enum Section: String, CaseIterable, Hashable {
        case overview = "Overview"
        case corners = "Corners"
        case moments = "Moments"
        case weather = "Weather"
    }

    enum DetailState {
        case loading
        case loaded(RideDetail)
        case failed(String)
    }

    let ride: Ride
    private(set) var state: DetailState = .loading
    var section: Section = .overview

    private let rideService: RideServing

    init(ride: Ride, rideService: RideServing) {
        self.ride = ride
        self.rideService = rideService
    }

    var detail: RideDetail? {
        if case .loaded(let d) = state { return d }
        return nil
    }

    var detailRoutePreview: [Coordinate]? {
        detail?.routePreview
    }

    /// Key headline stats shown under the title, available immediately.
    var headlineStats: [SegmentedMetric.Item] {
        [
            .init(value: ride.distanceFormatted, unit: "km", label: "Distance"),
            .init(value: ride.durationFormatted, unit: "", label: "Time"),
            .init(value: ride.elevationFormatted, unit: "m", label: "Ascent")
        ]
    }

    func load() async {
        state = .loading
        do {
            let detail = try await rideService.fetchDetail(for: ride)
            state = .loaded(detail)
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
