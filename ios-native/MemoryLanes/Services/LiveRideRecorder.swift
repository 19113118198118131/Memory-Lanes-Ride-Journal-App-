import Foundation
import CoreLocation

// MARK: - LiveRideRecorder
//
// Native Core Location recorder for real rides. It records only after the rider
// taps Start Ride, persists the active draft to disk after each useful point, and
// can export the captured track as GPX when the ride is finished.

@MainActor
final class LiveRideRecorder: NSObject, ObservableObject {
    @Published private(set) var status: RecordingStatus = .idle
    @Published private(set) var points: [RecordingPoint] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elevationGainMeters: Double = 0
    @Published private(set) var currentSpeedMetersPerSecond: Double = 0
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var lastErrorMessage: String?

    private let manager = CLLocationManager()
    private let fileManager: FileManager
    private var startedAt: Date?
    private var lastTick = Date()
    private var lastAcceptedLocation: CLLocation?
    private var timer: Timer?
    /// True only between the rider tapping Start and permission being granted,
    /// so an authorization callback never auto-starts a ride on its own.
    private var pendingStart = false
    /// Point count at the last on-disk snapshot, so the draft is persisted every
    /// so often rather than re-serialised on every single GPS fix.
    private var lastPersistedPointCount = 0
    /// Monotonic write sequence so out-of-order background writes/removes can't
    /// resurrect a stale or discarded draft.
    private var draftSequence = 0
    private lazy var draftPersister = DraftPersister(url: draftURL)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        authorization = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 8
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        restoreInterruptedDraftIfNeeded()
    }

    var isRecording: Bool { status == .recording }
    var isPaused: Bool { status == .paused }
    var pointCount: Int { points.count }

    var distanceKm: Double { distanceMeters / 1000 }

    var averageSpeedMetersPerSecond: Double {
        guard elapsed > 0 else { return 0 }
        return distanceMeters / elapsed
    }

    var routePreview: [Coordinate] {
        points.routePreview
    }

    var permissionSummary: String {
        switch authorization {
        case .authorizedAlways:
            return "Always location ready"
        case .authorizedWhenInUse:
            return "Recording in app; enable Always for locked screen"
        case .notDetermined:
            return "Location permission needed"
        case .restricted, .denied:
            return "Location permission blocked"
        @unknown default:
            return "Location status unknown"
        }
    }

    func start() {
        lastErrorMessage = nil
        switch authorization {
        case .notDetermined:
            // Remember that a start was requested so the authorization callback
            // knows this permission grant should actually begin recording.
            pendingStart = true
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginRecording()
        case .restricted, .denied:
            status = .permissionDenied
            lastErrorMessage = "Allow location access in Settings to record a ride."
        @unknown default:
            status = .permissionDenied
            lastErrorMessage = "Location permission is unavailable on this device."
        }
    }

    func pause() {
        guard status == .recording else { return }
        status = .paused
        currentSpeedMetersPerSecond = 0
        manager.stopUpdatingLocation()
        stopTimer()
        persistDraft(force: true)
    }

    func resume() {
        guard status == .paused else { return }
        status = .recording
        lastTick = Date()
        manager.startUpdatingLocation()
        startTimer()
        persistDraft(force: true)
    }

    func discard() {
        pendingStart = false
        stopLocationSession()
        points = []
        elapsed = 0
        distanceMeters = 0
        elevationGainMeters = 0
        currentSpeedMetersPerSecond = 0
        startedAt = nil
        lastAcceptedLocation = nil
        status = .idle
        removeDraft()
    }

    func finish(title: String = "Recorded Ride") -> RecordedRideResult? {
        guard !points.isEmpty else {
            discard()
            return nil
        }

        stopLocationSession()
        let result = RecordedRideResult(
            title: title,
            startedAt: startedAt ?? points.first?.timestamp ?? Date(),
            durationSeconds: elapsed,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            points: points,
            gpxText: GPXWriter.gpx(title: title, points: points)
        )
        writeCompletedGPX(result)
        removeDraft()
        status = .finished
        return result
    }

    private func beginRecording() {
        if points.isEmpty {
            startedAt = Date()
            elapsed = 0
            distanceMeters = 0
            elevationGainMeters = 0
            currentSpeedMetersPerSecond = 0
            lastAcceptedLocation = nil
            lastPersistedPointCount = 0
        }
        status = .recording
        lastTick = Date()
        persistDraft(force: true)
        manager.startUpdatingLocation()
        startTimer()
    }

    private func stopLocationSession() {
        manager.stopUpdatingLocation()
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard status == .recording else { return }
        let now = Date()
        elapsed += now.timeIntervalSince(lastTick)
        lastTick = now
        persistDraft()
    }

    private func accept(location: CLLocation) {
        guard status == .recording else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 80 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }

        let point = RecordingPoint(location: location)
        if let lastAcceptedLocation {
            let delta = location.distance(from: lastAcceptedLocation)
            guard delta >= 2 else { return }
            distanceMeters += delta

            let elevationDelta = location.altitude - lastAcceptedLocation.altitude
            if elevationDelta > 1.5 {
                elevationGainMeters += elevationDelta
            }
        }

        points.append(point)
        currentSpeedMetersPerSecond = point.speedMetersPerSecond
        lastAcceptedLocation = location
        persistDraft()
    }

    private var draftURL: URL {
        applicationSupportDirectory.appendingPathComponent("active-ride-draft.json")
    }

    private var completedDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("CompletedRides", isDirectory: true)
    }

    private var applicationSupportDirectory: URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let directory = urls[0].appendingPathComponent("MemoryLanes", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func persistDraft(force: Bool = false) {
        guard status == .recording || status == .paused else { return }
        // Snapshot every ~10 points (or on demand for state changes), not on
        // every GPS fix — and hand the encode + write to a background actor so
        // it never blocks the main thread, even on a multi-hour ride.
        if !force && points.count - lastPersistedPointCount < 10 { return }
        lastPersistedPointCount = points.count
        draftSequence += 1
        let sequence = draftSequence
        let draft = RecordingDraft(
            status: status,
            startedAt: startedAt,
            elapsed: elapsed,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            points: points
        )
        let persister = draftPersister
        Task { await persister.write(draft, sequence: sequence) }
    }

    private func restoreInterruptedDraftIfNeeded() {
        guard let data = try? Data(contentsOf: draftURL),
              let draft = try? JSONDecoder.recordingDecoder.decode(RecordingDraft.self, from: data),
              !draft.points.isEmpty else { return }

        points = draft.points
        elapsed = draft.elapsed
        distanceMeters = draft.distanceMeters
        elevationGainMeters = draft.elevationGainMeters
        startedAt = draft.startedAt
        lastAcceptedLocation = draft.points.last?.clLocation
        lastPersistedPointCount = draft.points.count
        currentSpeedMetersPerSecond = 0
        status = .paused
        lastErrorMessage = "Recovered an unfinished ride. Resume it or finish when ready."
    }

    private func removeDraft() {
        lastPersistedPointCount = 0
        draftSequence += 1
        let sequence = draftSequence
        let persister = draftPersister
        // Routed through the same actor as writes so a late in-flight write
        // can't recreate the draft file after it's been removed.
        Task { await persister.remove(sequence: sequence) }
    }

    private func writeCompletedGPX(_ result: RecordedRideResult) {
        do {
            try fileManager.createDirectory(at: completedDirectory, withIntermediateDirectories: true)
            let safeDate = DateFormatting.fileSafeString(from: result.startedAt)
            let url = completedDirectory.appendingPathComponent("\(safeDate)-ride.gpx")
            try result.gpxText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastErrorMessage = "Ride finished, but GPX export could not be written locally."
        }
    }
}

extension LiveRideRecorder: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        // This callback also fires when the delegate is first set and whenever
        // the rider returns from Settings, so we only begin recording when a
        // start was explicitly requested and is still waiting on permission.
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            if pendingStart {
                pendingStart = false
                beginRecording()
            }
        case .denied, .restricted:
            if pendingStart {
                pendingStart = false
                status = .permissionDenied
                lastErrorMessage = "Allow location access in Settings to record a ride."
            }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            accept(location: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastErrorMessage = error.localizedDescription
    }
}

enum RecordingStatus: String, Codable, Sendable {
    case idle
    case recording
    case paused
    case permissionDenied
    case finished
}

struct RecordedRideResult: Sendable {
    let title: String
    let startedAt: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let elevationGainMeters: Double
    let points: [RecordingPoint]
    let gpxText: String
}

private struct RecordingDraft: Codable, Sendable {
    let status: RecordingStatus
    let startedAt: Date?
    let elapsed: TimeInterval
    let distanceMeters: Double
    let elevationGainMeters: Double
    let points: [RecordingPoint]
}

// MARK: - DraftPersister
//
// Serialises the crash-recovery draft's disk I/O off the main thread. Writes and
// removes are ordered by a monotonic sequence so a slow, older write can never
// land after a newer write — or resurrect a draft that was already removed.

private actor DraftPersister {
    private let url: URL
    private var lastSequence = 0

    init(url: URL) { self.url = url }

    func write(_ draft: RecordingDraft, sequence: Int) {
        guard sequence > lastSequence else { return }
        lastSequence = sequence
        guard let data = try? JSONEncoder.recordingEncoder.encode(draft) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func remove(sequence: Int) {
        guard sequence > lastSequence else { return }
        lastSequence = sequence
        try? FileManager.default.removeItem(at: url)
    }
}

private enum GPXWriter {
    static func gpx(title: String, points: [RecordingPoint]) -> String {
        let trackPoints = points.map { point in
            """
            <trkpt lat="\(point.latitude)" lon="\(point.longitude)"><ele>\(point.elevationMeters)</ele><time>\(DateFormatting.gpxString(from: point.timestamp))</time></trkpt>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Memory Lanes" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(title.xmlEscaped)</name>
          </metadata>
          <trk>
            <name>\(title.xmlEscaped)</name>
            <trkseg>
        \(trackPoints)
            </trkseg>
          </trk>
        </gpx>
        """
    }
}

private extension JSONEncoder {
    static var recordingEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var recordingDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private enum DateFormatting {
    static func gpxString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func fileSafeString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        return formatter.string(from: date)
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
