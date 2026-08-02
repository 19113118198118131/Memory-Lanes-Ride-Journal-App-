import Combine
import Foundation
@preconcurrency import Network

struct PendingRideUpload: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let result: RecordedRideResult
    let plannedRouteID: UUID?
    let userID: UUID
    let enqueuedAt: Date
    var attemptCount: Int
    var lastAttemptAt: Date?
    var lastErrorDescription: String?

    init(
        title: String,
        result: RecordedRideResult,
        plannedRouteID: UUID?,
        userID: UUID,
        enqueuedAt: Date = Date()
    ) {
        id = result.id
        self.title = title
        self.result = result
        self.plannedRouteID = plannedRouteID
        self.userID = userID
        self.enqueuedAt = enqueuedAt
        attemptCount = 0
        lastAttemptAt = nil
        lastErrorDescription = nil
    }
}

protocol PendingRideUploadStoring: Sendable {
    func uploads(for userID: UUID) async -> [PendingRideUpload]
    func save(_ upload: PendingRideUpload) async throws
    func markFailed(id: UUID, errorDescription: String) async throws
    func remove(id: UUID) async throws
}

actor PendingRideUploadStore: PendingRideUploadStoring {
    static let shared = PendingRideUploadStore()

    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = directory
            ?? applicationSupport
                .appendingPathComponent("MemoryLanes", isDirectory: true)
                .appendingPathComponent("PendingRideUploads", isDirectory: true)
    }

    func uploads(for userID: UUID) -> [PendingRideUpload] {
        loadAll()
            .filter { $0.userID == userID }
            .sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    func save(_ upload: PendingRideUpload) throws {
        try prepareDirectory()
        let data = try Self.encoder.encode(upload)
        try data.write(to: url(for: upload.id), options: [.atomic, .completeFileProtection])
    }

    func markFailed(id: UUID, errorDescription: String) throws {
        guard var upload = load(id: id) else { return }
        upload.attemptCount += 1
        upload.lastAttemptAt = Date()
        upload.lastErrorDescription = errorDescription
        try save(upload)
    }

    func remove(id: UUID) throws {
        let fileURL = url(for: id)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func loadAll() -> [PendingRideUpload] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? Self.decoder.decode(PendingRideUpload.self, from: data)
        }
    }

    private func load(id: UUID) -> PendingRideUpload? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? Self.decoder.decode(PendingRideUpload.self, from: data)
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@MainActor
final class PendingRideUploadCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case syncing
        case waitingForConnection
    }

    enum SubmissionOutcome: Equatable {
        case synced
        case queued
    }

    @Published private(set) var pendingCount = 0
    @Published private(set) var phase: Phase = .idle

    private let store: any PendingRideUploadStoring
    private let uploader: any RecordedRideUploading
    private let monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "app.memorylanes.pending-ride-network")
    private var userID: UUID?
    private var accessToken: (@Sendable () async -> String?)?
    private var onUploaded: (@MainActor (Ride) -> Void)?

    init(
        store: any PendingRideUploadStoring = PendingRideUploadStore.shared,
        uploader: any RecordedRideUploading = RideImportService(),
        monitorsNetwork: Bool = true
    ) {
        self.store = store
        self.uploader = uploader

        if monitorsNetwork {
            let monitor = NWPathMonitor()
            self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in
                    await self?.sync()
                }
            }
            monitor.start(queue: monitorQueue)
        } else {
            monitor = nil
        }
    }

    deinit {
        monitor?.cancel()
    }

    func configure(
        userID: UUID?,
        accessToken: (@Sendable () async -> String?)?,
        onUploaded: (@MainActor (Ride) -> Void)? = nil
    ) async {
        self.userID = userID
        self.accessToken = accessToken
        self.onUploaded = onUploaded
        await refresh()
    }

    func submit(
        title: String,
        result: RecordedRideResult,
        plannedRouteID: UUID?,
        userID: UUID
    ) async throws -> SubmissionOutcome {
        try await store.save(PendingRideUpload(
            title: title,
            result: result,
            plannedRouteID: plannedRouteID,
            userID: userID
        ))
        await refresh()
        await sync()
        let stillPending = await store.uploads(for: userID).contains { $0.id == result.id }
        return stillPending ? .queued : .synced
    }

    func keepForLater(
        title: String,
        result: RecordedRideResult,
        plannedRouteID: UUID?,
        userID: UUID
    ) async throws {
        try await store.save(PendingRideUpload(
            title: title,
            result: result,
            plannedRouteID: plannedRouteID,
            userID: userID
        ))
        phase = .waitingForConnection
        await refresh()
    }

    func sync() async {
        guard phase != .syncing, let userID else { return }
        let uploads = await store.uploads(for: userID)
        pendingCount = uploads.count
        guard !uploads.isEmpty else {
            phase = .idle
            return
        }
        guard let token = await accessToken?() else {
            phase = .waitingForConnection
            return
        }

        phase = .syncing
        for upload in uploads {
            guard !Task.isCancelled else { break }
            do {
                let ride = try await uploader.saveRecordedRide(
                    title: upload.title,
                    result: upload.result,
                    plannedRouteID: upload.plannedRouteID,
                    userID: upload.userID,
                    accessToken: token
                )
                try await store.remove(id: upload.id)
                pendingCount -= 1
                onUploaded?(ride)
            } catch is CancellationError {
                break
            } catch {
                try? await store.markFailed(id: upload.id, errorDescription: error.localizedDescription)
                phase = .waitingForConnection
                await refresh()
                return
            }
        }
        await refresh()
        phase = pendingCount == 0 ? .idle : .waitingForConnection
    }

    func refresh() async {
        guard let userID else {
            pendingCount = 0
            phase = .idle
            return
        }
        pendingCount = await store.uploads(for: userID).count
        if pendingCount == 0, phase != .syncing {
            phase = .idle
        }
    }
}
