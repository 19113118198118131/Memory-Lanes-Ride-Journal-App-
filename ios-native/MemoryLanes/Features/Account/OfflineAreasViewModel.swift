import Foundation
import Observation

@MainActor
@Observable
final class OfflineAreasViewModel {
    private(set) var catalog: [OfflineRegionDescriptor] = []
    private(set) var installed: [InstalledOfflineRegion] = []
    private(set) var installPhases: [String: OfflineRegionInstallPhase] = [:]
    private(set) var isLoading = false
    private(set) var catalogError: String?
    private(set) var storageByteCount: Int64 = 0
    var wifiOnly: Bool {
        didSet { defaults.set(wifiOnly, forKey: Self.wifiOnlyKey) }
    }
    var toast: Toast?

    private let store: any OfflineRegionServing
    private let defaults: UserDefaults
    private static let wifiOnlyKey = "offlineAreas.wifiOnly"

    init(
        store: any OfflineRegionServing = OfflineRegionStore.shared,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.defaults = defaults
        self.wifiOnly = defaults.object(forKey: Self.wifiOnlyKey) as? Bool ?? true
    }

    var available: [OfflineRegionDescriptor] {
        catalog.sorted { $0.name < $1.name }
    }

    var storageText: String {
        ByteCountFormatter.string(fromByteCount: storageByteCount, countStyle: .file)
    }

    var readinessText: String {
        switch installed.count {
        case 0: "No offline areas"
        case 1: "1 area ready"
        default: "\(installed.count) areas ready"
        }
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        catalogError = nil
        async let installedRegions = store.installedRegions()
        async let storage = store.storageByteCount()

        do {
            catalog = try await store.catalog(forceRefresh: forceRefresh).regions
        } catch {
            catalogError = error.localizedDescription
        }
        installed = await installedRegions
        storageByteCount = await storage
        isLoading = false
    }

    func install(_ region: OfflineRegionDescriptor) async -> Bool {
        guard installPhases[region.id] == nil else { return false }
        installPhases[region.id] = .downloading
        do {
            _ = try await store.install(region, wifiOnly: wifiOnly) { [weak self] phase in
                await self?.setInstallPhase(phase, for: region.id)
            }
            installPhases[region.id] = nil
            await refreshInstalled()
            Haptics.success()
            toast = .success("\(region.name) is ready offline")
            return true
        } catch is CancellationError {
            installPhases[region.id] = nil
            return false
        } catch {
            installPhases[region.id] = nil
            Haptics.error()
            toast = .error(error.localizedDescription)
            return false
        }
    }

    func install(_ regions: [OfflineRegionDescriptor]) async -> Bool {
        var installedEveryRegion = true
        for region in regions where !isCurrent(region) {
            guard !Task.isCancelled else { return false }
            if !(await install(region)) { installedEveryRegion = false }
        }
        return installedEveryRegion
    }

    func remove(_ region: InstalledOfflineRegion) async {
        do {
            try await store.remove(regionID: region.id)
            await refreshInstalled()
            Haptics.success()
            toast = .success("\(region.descriptor.name) removed")
        } catch {
            Haptics.error()
            toast = .error(error.localizedDescription)
        }
    }

    func installedRegion(for descriptor: OfflineRegionDescriptor) -> InstalledOfflineRegion? {
        installed.first { $0.id == descriptor.id }
    }

    func isCurrent(_ descriptor: OfflineRegionDescriptor) -> Bool {
        guard let installed = installedRegion(for: descriptor) else { return false }
        return installed.descriptor.version >= descriptor.version
    }

    func regions(intersecting bounds: OfflineRegionBounds) -> [OfflineRegionDescriptor] {
        available.filter { $0.bounds.intersects(bounds) }
    }

    private func refreshInstalled() async {
        installed = await store.installedRegions()
        storageByteCount = await store.storageByteCount()
    }

    private func setInstallPhase(_ phase: OfflineRegionInstallPhase, for regionID: String) {
        installPhases[regionID] = phase
    }
}
