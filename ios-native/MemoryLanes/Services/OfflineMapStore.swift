import Foundation
@preconcurrency import MapLibre

@MainActor
protocol OfflineMapServing: AnyObject {
    func areas() async -> [OfflineMapArea]
    func download(
        name: String,
        draft: OfflineMapAreaDraft,
        progress: @escaping @MainActor (OfflineMapDownloadProgress) -> Void
    ) async throws -> OfflineMapArea
    func resume(areaID: UUID) async throws
    func rename(areaID: UUID, name: String) async throws
    func remove(areaID: UUID) async throws
}

@MainActor
final class MapLibreOfflineMapStore: OfflineMapServing {
    static let shared = MapLibreOfflineMapStore()
    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")

    private struct Context: Codable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let bounds: OfflineRegionBounds
        let createdAt: Date
        let minimumZoom: Double
        let maximumZoom: Double
    }

    private struct PackReference: @unchecked Sendable {
        let value: MLNOfflinePack
    }

    private let storage: MLNOfflineStorage

    init(storage: MLNOfflineStorage = .shared) {
        self.storage = storage
        storage.setMaximumAllowedMapboxTiles(250_000)
    }

    func areas() async -> [OfflineMapArea] {
        await waitForInitialPackLoad()
        let packs = storage.packs ?? []
        packs.forEach { $0.requestProgress() }
        if !packs.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return packs.compactMap(makeArea).sorted { $0.createdAt > $1.createdAt }
    }

    func download(
        name: String,
        draft: OfflineMapAreaDraft,
        progress: @escaping @MainActor (OfflineMapDownloadProgress) -> Void
    ) async throws -> OfflineMapArea {
        guard draft.bounds.isValid else { throw OfflineMapError.invalidSelection }
        guard let styleURL = Self.styleURL else { throw OfflineMapError.invalidStyleURL }

        let context = Context(
            schemaVersion: 1,
            id: UUID(),
            name: normalizedName(name),
            bounds: draft.bounds,
            createdAt: Date(),
            minimumZoom: draft.minimumZoom,
            maximumZoom: draft.maximumZoom
        )
        let contextData = try Self.encoder.encode(context)
        let bounds = MLNCoordinateBounds(
            sw: .init(latitude: draft.bounds.south, longitude: draft.bounds.west),
            ne: .init(latitude: draft.bounds.north, longitude: draft.bounds.east)
        )
        let region = MLNTilePyramidOfflineRegion(
            styleURL: styleURL,
            bounds: bounds,
            fromZoomLevel: draft.minimumZoom,
            toZoomLevel: draft.maximumZoom
        )
        region.includesIdeographicGlyphs = false

        let pack = try await addPack(region: region, context: contextData)
        pack.resume()

        do {
            var lastCompletedResourceCount: UInt64 = 0
            var lastProgressAt = ContinuousClock.now
            while !Task.isCancelled {
                pack.requestProgress()
                try await Task.sleep(for: .milliseconds(250))
                let snapshot = progressSnapshot(for: pack)
                progress(snapshot)
                if pack.state == .complete {
                    guard let area = makeArea(pack) else { throw OfflineMapError.metadataUnavailable }
                    return area
                }
                let completedResourceCount = pack.progress.countOfResourcesCompleted
                if completedResourceCount > lastCompletedResourceCount {
                    lastCompletedResourceCount = completedResourceCount
                    lastProgressAt = .now
                } else if ContinuousClock.now - lastProgressAt > .seconds(90) {
                    pack.suspend()
                    throw OfflineMapError.downloadFailed("The connection stopped responding. Try Resume when reception improves.")
                }
            }
            pack.suspend()
            throw CancellationError()
        } catch {
            if error is CancellationError { pack.suspend() }
            throw error
        }
    }

    func resume(areaID: UUID) async throws {
        guard let pack = await pack(for: areaID) else { throw OfflineMapError.packUnavailable }
        pack.resume()
    }

    func rename(areaID: UUID, name: String) async throws {
        guard let pack = await pack(for: areaID),
              let context = decodeContext(pack.context) else {
            throw OfflineMapError.packUnavailable
        }
        let updated = Context(
            schemaVersion: context.schemaVersion,
            id: context.id,
            name: normalizedName(name),
            bounds: context.bounds,
            createdAt: context.createdAt,
            minimumZoom: context.minimumZoom,
            maximumZoom: context.maximumZoom
        )
        let data = try Self.encoder.encode(updated)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pack.setContext(data) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    func remove(areaID: UUID) async throws {
        guard let pack = await pack(for: areaID) else { throw OfflineMapError.packUnavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            storage.removePack(pack) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func addPack(region: MLNTilePyramidOfflineRegion, context: Data) async throws -> MLNOfflinePack {
        let reference: PackReference = try await withCheckedThrowingContinuation { continuation in
            storage.addPack(for: region, withContext: context) { pack, error in
                if let error { continuation.resume(throwing: error) }
                else if let pack { continuation.resume(returning: PackReference(value: pack)) }
                else { continuation.resume(throwing: OfflineMapError.packUnavailable) }
            }
        }
        return reference.value
    }

    private func pack(for areaID: UUID) async -> MLNOfflinePack? {
        await waitForInitialPackLoad()
        return storage.packs?.first { pack in
            decodeContext(pack.context)?.id == areaID
        }
    }

    private func makeArea(_ pack: MLNOfflinePack) -> OfflineMapArea? {
        guard let context = decodeContext(pack.context) else { return nil }
        let snapshot = progressSnapshot(for: pack)
        return OfflineMapArea(
            id: context.id,
            name: context.name,
            bounds: context.bounds,
            createdAt: context.createdAt,
            minimumZoom: context.minimumZoom,
            maximumZoom: context.maximumZoom,
            bytesDownloaded: snapshot.bytesCompleted,
            progress: snapshot.fractionCompleted,
            status: status(for: pack)
        )
    }

    private func status(for pack: MLNOfflinePack) -> OfflineMapAreaStatus {
        switch pack.state {
        case .unknown: .preparing
        case .inactive: .paused
        case .active: .downloading
        case .complete: .complete
        case .invalid: .failed
        @unknown default: .failed
        }
    }

    private func progressSnapshot(for pack: MLNOfflinePack) -> OfflineMapDownloadProgress {
        let value = pack.progress
        let expected = value.countOfResourcesExpected
        let fraction = expected > 0
            ? min(max(Double(value.countOfResourcesCompleted) / Double(expected), 0), 1)
            : (pack.state == .complete ? 1 : 0)
        return OfflineMapDownloadProgress(
            fractionCompleted: fraction,
            bytesCompleted: Int64(clamping: value.countOfBytesCompleted)
        )
    }

    private func decodeContext(_ data: Data) -> Context? {
        guard let context = try? Self.decoder.decode(Context.self, from: data),
              context.schemaVersion == 1 else { return nil }
        return context
    }

    private func waitForInitialPackLoad() async {
        guard storage.packs == nil else { return }
        storage.reloadPacks()
        for _ in 0..<40 where storage.packs == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Offline Area" : String(trimmed.prefix(60))
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()
}
