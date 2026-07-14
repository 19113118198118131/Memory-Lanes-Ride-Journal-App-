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

    private(set) var ride: Ride
    private(set) var state: DetailState = .loading
    var section: Section = .overview
    var momentErrorMessage: String?
    var isSavingMoment = false
    var isUpdatingShareLink = false
    var isExportingGPX = false
    var shareErrorMessage: String?
    var playbackIndex = 0
    var isPlaying = false
    var playbackSpeed: Double = 1

    @ObservationIgnored private var playbackTask: Task<Void, Never>?

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
        if let replayRoute = detail?.replayPoints.map(\.coordinate), !replayRoute.isEmpty { return replayRoute }
        if let detailRoutePreview, !detailRoutePreview.isEmpty { return detailRoutePreview }
        return ride.routePreview
    }

    var plannedGuideRoute: [Coordinate] {
        detail?.plannedRoute?.route ?? []
    }

    var publicShareURL: URL? {
        ride.isPublic ? ride.publicShareURL : nil
    }

    var canReplay: Bool {
        (detail?.replayPoints.count ?? 0) > 1
    }

    var currentReplayPoint: ReplayPoint? {
        guard let points = detail?.replayPoints, !points.isEmpty else { return nil }
        return points[min(playbackIndex, points.count - 1)]
    }

    var mapReplayIndex: Int? {
        canReplay ? min(playbackIndex, max(routeForMomentPinning.count - 1, 0)) : nil
    }

    var playbackProgressText: String {
        guard let point = currentReplayPoint else { return "00:00" }
        return point.elapsedFormatted
    }

    var playbackDistanceText: String {
        guard let point = currentReplayPoint else { return "0.0 km" }
        return String(format: "%.1f km", point.distanceKm)
    }

    var playbackSpeedText: String {
        guard let point = currentReplayPoint else { return "0 km/h" }
        return "\(Int(point.speedKmh.rounded())) km/h"
    }

    var flowScoreText: String {
        if let score = detail?.coachScore ?? ride.flowScore {
            return "\(score)"
        }
        return "—"
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
            playbackIndex = min(playbackIndex, max(detail.replayPoints.count - 1, 0))
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func togglePlayback() {
        guard canReplay else { return }
        isPlaying ? pausePlayback() : startPlayback()
    }

    func pausePlayback() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        if isPlaying {
            startPlayback()
        }
    }

    func scrubPlayback(to index: Int) {
        pausePlayback()
        setPlaybackIndex(index)
    }

    private func startPlayback() {
        guard let count = detail?.replayPoints.count, count > 1 else { return }
        playbackTask?.cancel()
        isPlaying = true
        if playbackIndex >= count - 1 { playbackIndex = 0 }
        playbackTask = Task { @MainActor in
            while !Task.isCancelled, isPlaying {
                try? await Task.sleep(for: .milliseconds(Int(650 / max(playbackSpeed, 0.5))))
                guard !Task.isCancelled else { return }
                if playbackIndex >= count - 1 {
                    pausePlayback()
                    return
                }
                playbackIndex += 1
            }
        }
    }

    private func setPlaybackIndex(_ index: Int) {
        guard let count = detail?.replayPoints.count, count > 0 else {
            playbackIndex = 0
            return
        }
        playbackIndex = min(max(index, 0), count - 1)
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
        let replayPoint = detail.replayPoints.indices.contains(safeIndex) ? detail.replayPoints[safeIndex] : nil
        let moment = Moment(
            id: editingID ?? UUID(),
            title: cleanTitle,
            note: cleanNote,
            coordinate: replayPoint?.coordinate ?? route[safeIndex],
            routeIndex: safeIndex,
            speedKmh: replayPoint?.speedKmh,
            elevationMeters: replayPoint?.elevationMeters,
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

    func publicShareLink() async throws -> URL {
        if let publicShareURL {
            return publicShareURL
        }
        isUpdatingShareLink = true
        shareErrorMessage = nil
        defer { isUpdatingShareLink = false }
        do {
            let updated = try await rideService.setSharing(true, for: ride)
            ride = updated
            guard let url = updated.publicShareURL else {
                throw RideServiceError.sharingUnavailable
            }
            return url
        } catch {
            shareErrorMessage = error.localizedDescription
            throw error
        }
    }

    func revokePublicShareLink() async -> Bool {
        guard ride.isPublic else { return true }
        isUpdatingShareLink = true
        shareErrorMessage = nil
        defer { isUpdatingShareLink = false }
        do {
            ride = try await rideService.setSharing(false, for: ride)
            return true
        } catch {
            shareErrorMessage = error.localizedDescription
            return false
        }
    }

    func exportGPXFile() async throws -> URL {
        isExportingGPX = true
        shareErrorMessage = nil
        defer { isExportingGPX = false }
        do {
            let data = try await rideService.gpxData(for: ride)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(ride.gpxFileName)
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            shareErrorMessage = error.localizedDescription
            throw error
        }
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
