import CryptoKit
import Foundation
import Testing
@testable import MemoryLanes

struct OfflineRegionStoreTests {
    @Test func validPackIsVerifiedInstalledAndDiscoverableByCoverage() async throws {
        let harness = try Harness(packData: Data("connected-road-graph".utf8))
        let manifest = harness.manifest()
        await harness.network.setManifest(try harness.encode(manifest))

        let loaded = try await harness.store.catalog(forceRefresh: true)
        let phases = InstallPhaseProbe()
        let installed = try await harness.store.install(loaded.regions[0], wifiOnly: true) { phase in
            await phases.append(phase)
        }

        #expect(installed.id == harness.region.id)
        #expect(await harness.store.installedRegions().count == 1)
        #expect(await harness.store.storageByteCount() == Int64(harness.packData.count))
        #expect(await harness.store.localGraphURL(containing: harness.region.bounds.center) != nil)
        #expect(await phases.values == [.downloading, .verifying, .activating])
    }

    @Test func checksumFailureCannotActivateCorruptPack() async throws {
        let harness = try Harness(packData: Data("corrupt".utf8), checksumOverride: String(repeating: "a", count: 64))
        await harness.network.setManifest(try harness.encode(harness.manifest()))

        do {
            _ = try await harness.store.install(harness.region, wifiOnly: false) { _ in }
            Issue.record("Expected corrupt road data to be rejected")
        } catch let error as OfflineRegionError {
            #expect(error == .checksumMismatch)
        }

        #expect(await harness.store.installedRegions().isEmpty)
        #expect(await harness.store.localGraphURL(containing: harness.region.bounds.center) == nil)
    }

    @Test func cachedCatalogKeepsAreaManagementAvailableOffline() async throws {
        let harness = try Harness(packData: Data("graph".utf8))
        await harness.network.setManifest(try harness.encode(harness.manifest()))
        _ = try await harness.store.catalog(forceRefresh: true)
        await harness.network.failManifestRequests()

        let cached = try await harness.store.catalog(forceRefresh: true)
        #expect(cached.regions.map(\.id) == [harness.region.id])
    }

    @Test func removalDeletesCoverageWithoutTouchingOtherRegions() async throws {
        let harness = try Harness(packData: Data("graph".utf8))
        _ = try await harness.store.install(harness.region, wifiOnly: false) { _ in }
        try await harness.store.remove(regionID: harness.region.id)

        #expect(await harness.store.installedRegions().isEmpty)
        #expect(await harness.store.storageByteCount() == 0)
    }
}

private struct Harness {
    let rootURL: URL
    let packData: Data
    let region: OfflineRegionDescriptor
    let network: FakeOfflineRegionNetworkClient
    let store: OfflineRegionStore

    init(packData: Data, checksumOverride: String? = nil) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-region-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        self.rootURL = rootURL
        self.packData = packData
        let digest = SHA256.hash(data: packData).map { String(format: "%02x", $0) }.joined()
        self.region = OfflineRegionDescriptor(
            id: "nz-auckland-north",
            name: "Auckland North",
            detail: "Albany to Warkworth",
            bounds: OfflineRegionBounds(south: -36.9, west: 174.5, north: -36.2, east: 175.1),
            version: 1,
            formatVersion: 1,
            byteCount: Int64(packData.count),
            sha256: checksumOverride ?? digest,
            downloadPath: "packs/nz-auckland-north-v1.mlgraph",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let network = FakeOfflineRegionNetworkClient(packData: packData)
        self.network = network
        self.store = OfflineRegionStore(
            rootURL: rootURL,
            manifestURL: URL(string: "https://example.com/manifest.json"),
            publicBucketURL: URL(string: "https://example.com/offline-regions"),
            network: network
        )
    }

    func manifest() -> OfflineRegionManifest {
        OfflineRegionManifest(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            regions: [region]
        )
    }

    func encode(_ manifest: OfflineRegionManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }
}

private actor FakeOfflineRegionNetworkClient: OfflineRegionNetworkClient {
    private var manifestData = Data()
    private let packData: Data
    private var shouldFailManifest = false

    init(packData: Data) {
        self.packData = packData
    }

    func setManifest(_ data: Data) {
        manifestData = data
    }

    func failManifestRequests() {
        shouldFailManifest = true
    }

    func data(for _: URLRequest) async throws -> Data {
        if shouldFailManifest { throw URLError(.notConnectedToInternet) }
        return manifestData
    }

    func download(for _: URLRequest) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("road-pack-\(UUID().uuidString).mlgraph")
        try packData.write(to: url, options: .atomic)
        return url
    }
}

private actor InstallPhaseProbe {
    private(set) var values: [OfflineRegionInstallPhase] = []

    func append(_ phase: OfflineRegionInstallPhase) {
        values.append(phase)
    }
}
