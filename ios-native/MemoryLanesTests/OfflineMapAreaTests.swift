import Foundation
import Testing
@testable import MemoryLanes

struct OfflineMapAreaTests {
    @Test func downloadEstimateGrowsWithSelectedArea() {
        let center = Coordinate(latitude: -36.65, longitude: 174.785)
        let nearby = OfflineMapAreaDraft(
            bounds: .centered(at: center, sideKilometers: 25)
        )
        let touring = OfflineMapAreaDraft(
            bounds: .centered(at: center, sideKilometers: 120)
        )

        #expect(nearby.estimatedByteCount > 0)
        #expect(touring.estimatedByteCount > nearby.estimatedByteCount)
    }

    @Test func additionalStreetDetailIncreasesDownloadEstimate() {
        let bounds = OfflineRegionBounds.centered(
            at: Coordinate(latitude: -36.65, longitude: 174.785),
            sideKilometers: 25
        )
        let regional = OfflineMapAreaDraft(bounds: bounds, minimumZoom: 7, maximumZoom: 12)
        let street = OfflineMapAreaDraft(bounds: bounds, minimumZoom: 7, maximumZoom: 15)

        #expect(street.estimatedByteCount > regional.estimatedByteCount)
    }

    @Test func mapAreaStatusProducesPlainLanguageProgress() {
        let area = OfflineMapArea(
            id: UUID(),
            name: "Northland",
            bounds: OfflineRegionBounds(south: -36.8, west: 174.4, north: -36.2, east: 175),
            createdAt: Date(),
            minimumZoom: 7,
            maximumZoom: 15,
            bytesDownloaded: 12_000_000,
            progress: 0.42,
            status: .downloading
        )

        #expect(area.progressText == "Downloading 42%")
        #expect(!area.sizeText.isEmpty)
    }

    @Test @MainActor func areaDownloadAlsoInstallsMatchingOfflineRoutingData() async {
        let bounds = OfflineRegionBounds(
            south: -36.8,
            west: 174.5,
            north: -36.3,
            east: 174.9
        )
        let descriptor = makeRegion(bounds: bounds)
        let regionStore = BundledRegionStore(catalog: [descriptor])
        let mapStore = BundledMapStore()
        let defaults = UserDefaults(suiteName: "OfflineMapAreaTests.\(UUID().uuidString)") ?? .standard
        let viewModel = OfflineAreasViewModel(
            store: regionStore,
            mapStore: mapStore,
            routingTelemetry: EmptyRoutingTelemetry(),
            defaults: defaults
        )

        await viewModel.load()
        let downloaded = await viewModel.downloadMap(
            name: "Auckland North",
            draft: OfflineMapAreaDraft(bounds: bounds)
        )

        #expect(downloaded)
        #expect(await regionStore.installedRegions().map(\.id) == [descriptor.id])
        #expect(viewModel.mapAreas.count == 1)
        let capability = viewModel.mapAreas.first.map { viewModel.capability(for: $0) }
        #expect(capability?.level == .complete)
    }

    @Test @MainActor func removingAnAreaKeepsSharedRoutingDataUntilTheLastAreaIsRemoved() async {
        let bounds = OfflineRegionBounds(
            south: -36.8,
            west: 174.5,
            north: -36.3,
            east: 174.9
        )
        let descriptor = makeRegion(bounds: bounds)
        let regionStore = BundledRegionStore(catalog: [descriptor])
        let mapStore = BundledMapStore()
        let defaults = UserDefaults(suiteName: "OfflineMapAreaRemovalTests.\(UUID().uuidString)") ?? .standard
        let viewModel = OfflineAreasViewModel(
            store: regionStore,
            mapStore: mapStore,
            routingTelemetry: EmptyRoutingTelemetry(),
            defaults: defaults
        )

        await viewModel.load()
        _ = await viewModel.downloadMap(name: "North", draft: OfflineMapAreaDraft(bounds: bounds))
        _ = await viewModel.downloadMap(name: "Coast", draft: OfflineMapAreaDraft(bounds: bounds))
        #expect(viewModel.mapAreas.count == 2)

        guard let first = viewModel.mapAreas.first else {
            Issue.record("Expected the first downloaded area")
            return
        }
        await viewModel.removeMapArea(first)
        #expect(await regionStore.installedRegions().map(\.id) == [descriptor.id])

        guard let last = viewModel.mapAreas.first else {
            Issue.record("Expected the remaining downloaded area")
            return
        }
        await viewModel.removeMapArea(last)
        #expect(await regionStore.installedRegions().isEmpty)
    }

    @Test func capabilityCopyExplainsMapOnlyAndNavigationReadyStates() {
        let mapOnly = OfflineAreaCapability(
            level: .mapOnly,
            installedCoverage: 0,
            publishedCoverage: 0
        )
        let ready = OfflineAreaCapability(
            level: .complete,
            installedCoverage: 1,
            publishedCoverage: 1
        )

        #expect(mapOnly.title == "Map ready offline")
        #expect(mapOnly.detail.contains("not been published"))
        #expect(ready.title == "Map + navigation ready")
        #expect(ready.detail.contains("without reception"))
    }

    private func makeRegion(bounds: OfflineRegionBounds) -> OfflineRegionDescriptor {
        OfflineRegionDescriptor(
            id: "nz-auckland-north",
            name: "Auckland North",
            detail: "North Shore and Hibiscus Coast",
            bounds: bounds,
            version: 1,
            formatVersion: 1,
            encoding: .deflateJSON,
            byteCount: 6_000_000,
            sha256: String(repeating: "a", count: 64),
            downloadPath: "packs/nz-auckland-north-v1.mlgraph",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

private actor BundledRegionStore: OfflineRegionServing {
    let catalogRegions: [OfflineRegionDescriptor]
    private var installed: [InstalledOfflineRegion] = []

    init(catalog: [OfflineRegionDescriptor]) {
        catalogRegions = catalog
    }

    func catalog(forceRefresh _: Bool) async throws -> OfflineRegionManifest {
        OfflineRegionManifest(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            regions: catalogRegions
        )
    }

    func installedRegions() async -> [InstalledOfflineRegion] { installed }

    func install(
        _ region: OfflineRegionDescriptor,
        wifiOnly _: Bool,
        progress: @Sendable @escaping (OfflineRegionInstallPhase) async -> Void
    ) async throws -> InstalledOfflineRegion {
        await progress(.downloading)
        await progress(.verifying)
        await progress(.activating)
        let value = InstalledOfflineRegion(
            descriptor: region,
            installedAt: Date(timeIntervalSince1970: 1_000),
            localFileName: "\(region.id).mlgraph"
        )
        installed.removeAll { $0.id == region.id }
        installed.append(value)
        return value
    }

    func remove(regionID: String) async throws {
        installed.removeAll { $0.id == regionID }
    }

    func storageByteCount() async -> Int64 {
        installed.reduce(0) { $0 + $1.descriptor.byteCount }
    }

    func localGraph(containing _: Coordinate) async -> InstalledOfflineRoadGraph? { nil }
}

@MainActor
private final class BundledMapStore: OfflineMapServing {
    private var storedAreas: [OfflineMapArea] = []

    func areas() async -> [OfflineMapArea] { storedAreas }

    func download(
        name: String,
        draft: OfflineMapAreaDraft,
        progress: @escaping @MainActor (OfflineMapDownloadProgress) -> Void
    ) async throws -> OfflineMapArea {
        progress(OfflineMapDownloadProgress(fractionCompleted: 1, bytesCompleted: 2_000_000))
        let area = OfflineMapArea(
            id: UUID(),
            name: name,
            bounds: draft.bounds,
            createdAt: Date(timeIntervalSince1970: 1_000),
            minimumZoom: draft.minimumZoom,
            maximumZoom: draft.maximumZoom,
            bytesDownloaded: 2_000_000,
            progress: 1,
            status: .complete
        )
        storedAreas.append(area)
        return area
    }

    func resume(areaID _: UUID) async throws {}
    func rename(areaID _: UUID, name _: String) async throws {}
    func remove(areaID: UUID) async throws { storedAreas.removeAll { $0.id == areaID } }
}

private actor EmptyRoutingTelemetry: OfflineRoutingTelemetryServing {
    func record(_: OfflineRoutingTelemetryEvent) async {}
    func diagnostics() async -> OfflineRoutingDiagnostics { .empty }
    func reset() async {}
}
