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
    var momentErrorMessage: String?
    var isSavingMoment = false

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

    var routeForMomentPinning: [Coordinate] {
        if let detailRoutePreview, !detailRoutePreview.isEmpty { return detailRoutePreview }
        return ride.routePreview
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

    func saveMoment(
        editingID: UUID?,
        title: String,
        note: String,
        routeIndex: Int
    ) async -> Bool {
        guard case .loaded(var detail) = state else { return false }
        let route = routeForMomentPinning
        guard !route.isEmpty else {
            momentErrorMessage = "This ride needs a route before moments can be pinned."
            return false
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty || !cleanNote.isEmpty else {
            momentErrorMessage = "Add a title or note before saving."
            return false
        }

        let safeIndex = min(max(routeIndex, 0), route.count - 1)
        let moment = Moment(
            id: editingID ?? UUID(),
            title: cleanTitle,
            note: cleanNote,
            coordinate: route[safeIndex],
            routeIndex: safeIndex,
            symbol: cleanNote.isEmpty ? "mappin.circle.fill" : "note.text"
        )

        if let editingID, let index = detail.moments.firstIndex(where: { $0.id == editingID }) {
            detail.moments[index] = moment
        } else {
            guard detail.moments.count < 5 else {
                momentErrorMessage = "You can pin up to five moments per ride."
                return false
            }
            detail.moments.append(moment)
        }

        return await persistMoments(detail.moments, detail: detail)
    }

    func deleteMoment(_ moment: Moment) async -> Bool {
        guard case .loaded(var detail) = state else { return false }
        detail.moments.removeAll { $0.id == moment.id }
        return await persistMoments(detail.moments, detail: detail)
    }

    private func persistMoments(_ moments: [Moment], detail: RideDetail) async -> Bool {
        isSavingMoment = true
        momentErrorMessage = nil
        do {
            let saved = try await rideService.saveMoments(moments, for: ride)
            var updated = detail
            updated.moments = saved
            state = .loaded(updated)
            isSavingMoment = false
            return true
        } catch {
            momentErrorMessage = error.localizedDescription
            isSavingMoment = false
            return false
        }
    }
}
