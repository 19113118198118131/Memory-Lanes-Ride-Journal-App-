import CryptoKit
import Foundation

protocol OfflineRegionServing: Sendable {
    func catalog(forceRefresh: Bool) async throws -> OfflineRegionManifest
    func installedRegions() async -> [InstalledOfflineRegion]
    func install(
        _ region: OfflineRegionDescriptor,
        wifiOnly: Bool,
        progress: @Sendable @escaping (OfflineRegionInstallPhase) async -> Void
    ) async throws -> InstalledOfflineRegion
    func remove(regionID: String) async throws
    func storageByteCount() async -> Int64
    func localGraph(containing coordinate: Coordinate) async -> InstalledOfflineRoadGraph?
}

protocol OfflineRegionNetworkClient: Sendable {
    func data(for request: URLRequest) async throws -> Data
    func download(for request: URLRequest) async throws -> URL
}

struct URLSessionOfflineRegionNetworkClient: OfflineRegionNetworkClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return data
    }

    func download(for request: URLRequest) async throws -> URL {
        let (url, response) = try await session.download(for: request)
        try Self.validate(response)
        return url
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OfflineRegionError.invalidServerResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw OfflineRegionError.server(status: http.statusCode)
        }
    }
}

actor OfflineRegionStore: OfflineRegionServing {
    static let shared = OfflineRegionStore()
    static let supportedManifestVersion = 1
    static let supportedGraphFormatVersion = 1

    static let productionManifestKeys: [String: Data] = [
        "release-2026-01": Data(base64Encoded: "I+N3zbgFy2UamDV/zHMphfpTrTb5IhqvrpZNV6Re7Rk=") ?? Data()
    ]

    private struct InstalledArchive: Codable {
        let schemaVersion: Int
        var regions: [InstalledOfflineRegion]

        init(regions: [InstalledOfflineRegion]) {
            schemaVersion = 1
            self.regions = regions
        }
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let manifestURL: URL
    private let publicBucketURL: URL
    private let network: any OfflineRegionNetworkClient
    private let trustedManifestKeys: [String: Data]
    private var installedCache: [InstalledOfflineRegion]?

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        manifestURL: URL? = nil,
        publicBucketURL: URL? = nil,
        network: any OfflineRegionNetworkClient = URLSessionOfflineRegionNetworkClient(),
        trustedManifestKeys: [String: Data] = OfflineRegionStore.productionManifestKeys
    ) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.rootURL = rootURL
            ?? applicationSupport
                .appendingPathComponent("MemoryLanes", isDirectory: true)
                .appendingPathComponent("OfflineRegions", isDirectory: true)
        let bucketURL = publicBucketURL
            ?? SupabaseConfig.url.appendingPathComponent("storage/v1/object/public/offline-regions", isDirectory: true)
        self.publicBucketURL = bucketURL
        self.manifestURL = manifestURL ?? bucketURL.appendingPathComponent("manifest.json")
        self.network = network
        self.trustedManifestKeys = trustedManifestKeys
    }

    func catalog(forceRefresh: Bool = false) async throws -> OfflineRegionManifest {
        if !forceRefresh, let cached = loadCachedManifest() { return cached }

        do {
            var request = URLRequest(url: manifestURL)
            request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
            let data = try await network.data(for: request)
            let manifest = try decodeVerifiedManifest(from: data)
            try validate(manifest)
            try createRootDirectory()
            try data.write(to: cachedManifestURL, options: .atomic)
            return manifest
        } catch {
            if let cached = loadCachedManifest() { return cached }
            if let offlineError = error as? OfflineRegionError { throw offlineError }
            throw OfflineRegionError.catalogUnavailable(error.localizedDescription)
        }
    }

    func installedRegions() async -> [InstalledOfflineRegion] {
        let regions = loadInstalledArchive().regions.filter { region in
            fileManager.fileExists(atPath: rootURL.appendingPathComponent(region.localFileName).path)
        }
        if regions.count != loadInstalledArchive().regions.count {
            try? persistInstalled(regions)
        }
        return regions.sorted { $0.descriptor.name < $1.descriptor.name }
    }

    func install(
        _ region: OfflineRegionDescriptor,
        wifiOnly: Bool,
        progress: @Sendable @escaping (OfflineRegionInstallPhase) async -> Void
    ) async throws -> InstalledOfflineRegion {
        try validate(region)
        try createRootDirectory()
        try ensureCapacity(for: region.byteCount)

        await progress(.downloading)
        var request = URLRequest(url: try downloadURL(for: region))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.allowsCellularAccess = !wifiOnly
        request.allowsExpensiveNetworkAccess = !wifiOnly
        request.allowsConstrainedNetworkAccess = !wifiOnly
        let temporaryDownload = try await network.download(for: request)

        await progress(.verifying)
        let attributes = try fileManager.attributesOfItem(atPath: temporaryDownload.path)
        let downloadedSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard downloadedSize == region.byteCount else {
            throw OfflineRegionError.sizeMismatch(expected: region.byteCount, actual: downloadedSize)
        }
        let digest = try Self.sha256(of: temporaryDownload)
        guard digest.caseInsensitiveCompare(region.sha256) == .orderedSame else {
            throw OfflineRegionError.checksumMismatch
        }

        await progress(.activating)
        let fileName = "\(region.id)-v\(region.version).mlgraph"
        let stagingURL = rootURL.appendingPathComponent(".staging-\(UUID().uuidString).mlgraph")
        try fileManager.copyItem(at: temporaryDownload, to: stagingURL)
        let destinationURL = rootURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        }

        var installed = loadInstalledArchive().regions
        let previousFiles = installed
            .filter { $0.id == region.id && $0.localFileName != fileName }
            .map(\.localFileName)
        installed.removeAll { $0.id == region.id }
        let value = InstalledOfflineRegion(
            descriptor: region,
            installedAt: Date(),
            localFileName: fileName
        )
        installed.append(value)
        try persistInstalled(installed)
        for previousFile in previousFiles {
            try? fileManager.removeItem(at: rootURL.appendingPathComponent(previousFile))
        }
        return value
    }

    func remove(regionID: String) async throws {
        var installed = loadInstalledArchive().regions
        let removed = installed.filter { $0.id == regionID }
        installed.removeAll { $0.id == regionID }
        try persistInstalled(installed)
        for region in removed {
            try? fileManager.removeItem(at: rootURL.appendingPathComponent(region.localFileName))
        }
    }

    func storageByteCount() async -> Int64 {
        await installedRegions().reduce(0) { $0 + $1.descriptor.byteCount }
    }

    func localGraph(containing coordinate: Coordinate) async -> InstalledOfflineRoadGraph? {
        let candidates = await installedRegions()
            .filter { $0.descriptor.bounds.contains(coordinate) }
            .sorted { $0.descriptor.version > $1.descriptor.version }
        guard let region = candidates.first else { return nil }
        let url = rootURL.appendingPathComponent(region.localFileName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return InstalledOfflineRoadGraph(
            regionID: region.id,
            regionName: region.descriptor.name,
            version: region.descriptor.version,
            fileURL: url
        )
    }

    private func downloadURL(for region: OfflineRegionDescriptor) throws -> URL {
        let path = region.downloadPath
        guard !path.hasPrefix("/"), !path.contains(".."), path.hasSuffix(".mlgraph") else {
            throw OfflineRegionError.invalidDownloadPath
        }
        return publicBucketURL.appendingPathComponent(path)
    }

    private func validate(_ manifest: OfflineRegionManifest) throws {
        guard manifest.schemaVersion == Self.supportedManifestVersion else {
            throw OfflineRegionError.unsupportedManifest
        }
        guard Set(manifest.regions.map(\.id)).count == manifest.regions.count else {
            throw OfflineRegionError.invalidManifest
        }
        try manifest.regions.forEach(validate)
    }

    private func decodeVerifiedManifest(from data: Data) throws -> OfflineRegionManifest {
        let envelope: SignedOfflineRegionManifestEnvelope
        do {
            envelope = try Self.decoder.decode(SignedOfflineRegionManifestEnvelope.self, from: data)
        } catch {
            throw OfflineRegionError.invalidManifestSignature
        }
        guard envelope.schemaVersion == 1,
              let publicKeyData = trustedManifestKeys[envelope.keyID],
              publicKeyData.count == 32,
              let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData),
              publicKey.isValidSignature(signature, for: payload) else {
            throw OfflineRegionError.invalidManifestSignature
        }
        do {
            let manifest = try Self.decoder.decode(OfflineRegionManifest.self, from: payload)
            try validate(manifest)
            return manifest
        } catch let error as OfflineRegionError {
            throw error
        } catch {
            throw OfflineRegionError.invalidManifest
        }
    }

    private func validate(_ region: OfflineRegionDescriptor) throws {
        let isHexDigest = region.sha256.count == 64 && region.sha256.allSatisfy { $0.isHexDigit }
        guard !region.id.isEmpty,
              !region.name.isEmpty,
              region.bounds.isValid,
              region.version > 0,
              region.formatVersion == Self.supportedGraphFormatVersion,
              region.encoding == .deflateJSON,
              region.byteCount > 0,
              isHexDigest else {
            throw OfflineRegionError.invalidManifest
        }
        _ = try downloadURL(for: region)
    }

    private func ensureCapacity(for byteCount: Int64) throws {
        let attributes = try fileManager.attributesOfFileSystem(forPath: rootURL.path)
        let available = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? .max
        let required = byteCount + max(byteCount / 5, 10_000_000)
        guard available >= required else {
            throw OfflineRegionError.insufficientStorage(required: required, available: available)
        }
    }

    private func loadCachedManifest() -> OfflineRegionManifest? {
        guard let data = try? Data(contentsOf: cachedManifestURL),
              let manifest = try? decodeVerifiedManifest(from: data) else { return nil }
        return manifest
    }

    private func loadInstalledArchive() -> InstalledArchive {
        if let installedCache { return InstalledArchive(regions: installedCache) }
        guard let data = try? Data(contentsOf: installedIndexURL),
              let archive = try? Self.decoder.decode(InstalledArchive.self, from: data),
              archive.schemaVersion == 1 else {
            installedCache = []
            return InstalledArchive(regions: [])
        }
        installedCache = archive.regions
        return archive
    }

    private func persistInstalled(_ regions: [InstalledOfflineRegion]) throws {
        try createRootDirectory()
        let data = try Self.encoder.encode(InstalledArchive(regions: regions))
        try data.write(to: installedIndexURL, options: .atomic)
        installedCache = regions
    }

    private func createRootDirectory() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private var cachedManifestURL: URL {
        rootURL.appendingPathComponent("manifest.json")
    }

    private var installedIndexURL: URL {
        rootURL.appendingPathComponent("installed.json")
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }()
}

enum OfflineRegionError: LocalizedError, Equatable {
    case catalogUnavailable(String)
    case invalidServerResponse
    case server(status: Int)
    case unsupportedManifest
    case invalidManifest
    case invalidManifestSignature
    case invalidDownloadPath
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch
    case insufficientStorage(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            return "Offline areas could not be loaded. Check your connection and try again."
        case .invalidServerResponse:
            return "The offline-area server returned an invalid response."
        case .server(let status):
            return "The offline-area server returned error \(status)."
        case .unsupportedManifest:
            return "This offline-area catalog needs a newer version of Memory Lanes."
        case .invalidManifest, .invalidDownloadPath:
            return "The offline-area catalog did not pass validation."
        case .invalidManifestSignature:
            return "The offline-area catalog could not be verified and was not accepted."
        case .sizeMismatch:
            return "The road pack was incomplete and was not installed."
        case .checksumMismatch:
            return "The road pack did not pass its integrity check and was not installed."
        case .insufficientStorage(let required, let available):
            let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availableText = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "This download needs \(requiredText), but only \(availableText) is available."
        }
    }
}
