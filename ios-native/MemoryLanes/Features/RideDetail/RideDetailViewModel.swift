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
        case overview = "Ride"
        case analytics = "Analytics"
        case corners = "Corners"
        case moments = "Journal"
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
    var feedbackStatus: String?
    var isSavingFeedback = false
    var playbackIndex = 0
    var playbackElapsedSeconds: TimeInterval = 0
    var isPlaying = false
    var playbackSpeed: Double = 1
    private(set) var calibrationReviews: [String: RiderCraftCalibrationReview] = [:]
    var calibrationReviewErrorMessage: String?
    var isExportingCalibrationReviews = false

    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var feedbackSaveTask: Task<Void, Never>?
    @ObservationIgnored private var feedbackSaveID = UUID()

    private let rideService: RideServing
    private let calibrationReviewStore: any RiderCraftCalibrationReviewStoring

    init(
        ride: Ride,
        rideService: RideServing,
        calibrationReviewStore: any RiderCraftCalibrationReviewStoring = RiderCraftCalibrationReviewStore.shared
    ) {
        self.ride = ride
        self.rideService = rideService
        self.calibrationReviewStore = calibrationReviewStore
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

    var calibrationReviewTargets: [RiderCraftCalibrationReviewTarget] {
        detail?.riderCraft?.calibrationReviewTargets ?? []
    }

    var calibrationReviewedCount: Int {
        calibrationReviewTargets.filter { calibrationReviews[$0.id] != nil }.count
    }

    var calibrationReviewSummary: RiderCraftCalibrationReviewSummary {
        RiderCraftCalibrationReviewSummary(reviews: Array(calibrationReviews.values))
    }

    var currentReplayPoint: ReplayPoint? {
        guard let points = detail?.replayPoints, !points.isEmpty else { return nil }
        return points[min(playbackIndex, points.count - 1)]
    }

    var currentReplayCoordinate: Coordinate? {
        guard let points = detail?.replayPoints, !points.isEmpty else { return nil }
        let currentIndex = min(playbackIndex, points.count - 1)
        let current = points[currentIndex]
        guard currentIndex + 1 < points.count else { return current.coordinate }
        let next = points[currentIndex + 1]
        let interval = next.elapsedSeconds - current.elapsedSeconds
        guard interval > 0 else { return current.coordinate }
        let progress = min(max((playbackElapsedSeconds - current.elapsedSeconds) / interval, 0), 1)
        return Coordinate(
            latitude: current.coordinate.latitude + (next.coordinate.latitude - current.coordinate.latitude) * progress,
            longitude: current.coordinate.longitude + (next.coordinate.longitude - current.coordinate.longitude) * progress
        )
    }

    var completedReplayRoute: [Coordinate] {
        guard let points = detail?.replayPoints, !points.isEmpty else { return [] }
        let endIndex = min(playbackIndex, points.count - 1)
        var completed = points.prefix(endIndex + 1).map(\.coordinate)
        if let currentReplayCoordinate, completed.last != currentReplayCoordinate {
            completed.append(currentReplayCoordinate)
        }
        return completed
    }

    var mapReplayIndex: Int? {
        canReplay ? min(playbackIndex, max(routeForMomentPinning.count - 1, 0)) : nil
    }

    var playbackProgressText: String {
        formatElapsed(playbackElapsedSeconds)
    }

    var playbackDistanceText: String {
        String(format: "%.1f km", interpolatedReplayValue(\.distanceKm))
    }

    var playbackSpeedText: String {
        "\(Int(interpolatedReplayValue(\.speedKmh).rounded())) km/h"
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
            playbackElapsedSeconds = detail.replayPoints.indices.contains(playbackIndex)
                ? detail.replayPoints[playbackIndex].elapsedSeconds
                : 0
            await loadCalibrationReviews(for: detail.riderCraft)
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func queueFeedbackSave(_ feedback: RideFeedback) {
        guard case .loaded(var detail) = state else { return }
        detail.feedback = feedback
        state = .loaded(detail)
        feedbackStatus = nil
        feedbackSaveTask?.cancel()
        let saveID = UUID()
        feedbackSaveID = saveID
        feedbackSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.persistFeedback(feedback, saveID: saveID)
        }
    }

    private func persistFeedback(_ feedback: RideFeedback, saveID: UUID) async {
        isSavingFeedback = true
        defer {
            if feedbackSaveID == saveID { isSavingFeedback = false }
        }
        do {
            let saved = try await rideService.saveFeedback(feedback, for: ride)
            guard feedbackSaveID == saveID, case .loaded(var currentDetail) = state else { return }
            currentDetail.feedback = saved
            state = .loaded(currentDetail)
            feedbackStatus = "Saved. This shapes your route matches."
        } catch is CancellationError {
        } catch {
            if feedbackSaveID == saveID { feedbackStatus = "Could not save feedback." }
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

    func focusCalibrationTarget(_ target: RiderCraftCalibrationReviewTarget) {
        scrubPlayback(to: target.replayIndex)
    }

    func calibrationDecision(for target: RiderCraftCalibrationReviewTarget) -> RiderCraftCalibrationReview.Decision? {
        calibrationReviews[target.id]?.decision
    }

    func calibrationSuspectedKind(for target: RiderCraftCalibrationReviewTarget) -> RiderCraftEvent.Kind? {
        calibrationReviews[target.id]?.suspectedKind
    }

    func saveCalibrationDecision(
        _ decision: RiderCraftCalibrationReview.Decision,
        for target: RiderCraftCalibrationReviewTarget,
        suspectedKind: RiderCraftEvent.Kind? = nil
    ) async -> Bool {
        guard let analysis = detail?.riderCraft else { return false }
        let review = RiderCraftCalibrationReview(
            rideID: ride.id,
            thresholdVersion: analysis.thresholdVersion,
            targetID: target.id,
            candidateKind: target.candidateKind,
            cornerIndex: target.cornerIndex,
            replayIndex: target.replayIndex,
            measuredValue: target.measuredValue,
            threshold: target.threshold,
            suspectedKind: target.isControl && decision == .mismatch ? suspectedKind : nil,
            decision: decision,
            reviewedAt: Date()
        )
        do {
            try await calibrationReviewStore.save(review)
            calibrationReviews[target.id] = review
            calibrationReviewErrorMessage = nil
            return true
        } catch {
            calibrationReviewErrorMessage = error.localizedDescription
            return false
        }
    }

    func exportCalibrationReviews() async throws -> URL {
        isExportingCalibrationReviews = true
        calibrationReviewErrorMessage = nil
        defer { isExportingCalibrationReviews = false }
        do {
            return try await calibrationReviewStore.makeExportFile()
        } catch {
            calibrationReviewErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func startPlayback() {
        guard let count = detail?.replayPoints.count, count > 1 else { return }
        playbackTask?.cancel()
        isPlaying = true
        if playbackIndex >= count - 1 {
            setPlaybackTime(0)
        }
        playbackTask = Task { @MainActor in
            var previousTick = Date()
            while !Task.isCancelled, isPlaying {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                let now = Date()
                let tickDuration = min(max(now.timeIntervalSince(previousTick), 0), 0.25)
                previousTick = now
                let endTime = detail?.replayPoints.last?.elapsedSeconds ?? 0
                let nextTime = min(playbackElapsedSeconds + tickDuration * playbackSpeed, endTime)
                setPlaybackTime(nextTime)
                if nextTime >= endTime {
                    pausePlayback()
                    return
                }
            }
        }
    }

    private func setPlaybackIndex(_ index: Int) {
        guard let count = detail?.replayPoints.count, count > 0 else {
            playbackIndex = 0
            playbackElapsedSeconds = 0
            return
        }
        playbackIndex = min(max(index, 0), count - 1)
        playbackElapsedSeconds = detail?.replayPoints[playbackIndex].elapsedSeconds ?? 0
    }

    private func setPlaybackTime(_ elapsed: TimeInterval) {
        guard let points = detail?.replayPoints, !points.isEmpty else {
            playbackIndex = 0
            playbackElapsedSeconds = 0
            return
        }
        let endTime = points.last?.elapsedSeconds ?? 0
        playbackElapsedSeconds = min(max(elapsed, 0), endTime)

        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if points[middle].elapsedSeconds <= playbackElapsedSeconds {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        playbackIndex = min(max(lower - 1, 0), points.count - 1)
    }

    private func interpolatedReplayValue(_ keyPath: KeyPath<ReplayPoint, Double>) -> Double {
        guard let points = detail?.replayPoints, !points.isEmpty else { return 0 }
        let currentIndex = min(playbackIndex, points.count - 1)
        let current = points[currentIndex]
        guard currentIndex + 1 < points.count else { return current[keyPath: keyPath] }
        let next = points[currentIndex + 1]
        let interval = next.elapsedSeconds - current.elapsedSeconds
        guard interval > 0 else { return current[keyPath: keyPath] }
        let progress = min(max((playbackElapsedSeconds - current.elapsedSeconds) / interval, 0), 1)
        return current[keyPath: keyPath] + (next[keyPath: keyPath] - current[keyPath: keyPath]) * progress
    }

    private func loadCalibrationReviews(for analysis: RiderCraftAnalysis?) async {
        guard let analysis else {
            calibrationReviews = [:]
            return
        }
        do {
            let reviews = try await calibrationReviewStore.reviews(
                for: ride.id,
                thresholdVersion: analysis.thresholdVersion
            )
            calibrationReviews = Dictionary(uniqueKeysWithValues: reviews.map { ($0.targetID, $0) })
            calibrationReviewErrorMessage = nil
        } catch {
            calibrationReviews = [:]
            calibrationReviewErrorMessage = error.localizedDescription
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
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
