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
    private(set) var routingDiagnostics = OfflineRoutingDiagnostics.empty
    var wifiOnly: Bool {
        didSet { defaults.set(wifiOnly, forKey: Self.wifiOnlyKey) }
    }
    var toast: Toast?

    private let store: any OfflineRegionServing
    private let routingTelemetry: any OfflineRoutingTelemetryServing
    private let defaults: UserDefaults
    private static let wifiOnlyKey = "offlineAreas.wifiOnly"

    init(
        store: any OfflineRegionServing = OfflineRegionStore.shared,
        routingTelemetry: any OfflineRoutingTelemetryServing = OfflineRoutingTelemetryStore.shared,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.routingTelemetry = routingTelemetry
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

    var routingDiagnosticsSummary: String {
        let local = routingDiagnostics.localRouteCount
        let fallback = routingDiagnostics.fallbackCount
        guard local + fallback > 0 else { return "No offline routing attempts yet" }
        return "\(local) local · \(fallback) fallback"
    }

    var lastRoutingPackText: String {
        guard let version = routingDiagnostics.lastRegionVersion else { return "No pack used yet" }
        let name = routingDiagnostics.lastRegionName
            ?? routingDiagnostics.lastRegionID
            ?? "Downloaded roads"
        return "\(name) · v\(version)"
    }

    var lastFallbackText: String {
        routingDiagnostics.lastFallbackReason?.title ?? "None"
    }

    var lastRoutingDurationText: String {
        guard let milliseconds = routingDiagnostics.lastDurationMilliseconds else { return "--" }
        if milliseconds < 1_000 { return "\(milliseconds) ms" }
        return String(format: "%.1f s", Double(milliseconds) / 1_000)
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        catalogError = nil
        async let installedRegions = store.installedRegions()
        async let storage = store.storageByteCount()
        async let diagnostics = routingTelemetry.diagnostics()

        do {
            catalog = try await store.catalog(forceRefresh: forceRefresh).regions
        } catch {
            catalogError = error.localizedDescription
        }
        installed = await installedRegions
        storageByteCount = await storage
        routingDiagnostics = await diagnostics
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

    func resetRoutingDiagnostics() async {
        await routingTelemetry.reset()
        routingDiagnostics = await routingTelemetry.diagnostics()
        Haptics.selection()
        toast = .success("Routing diagnostics reset")
    }

    private func refreshInstalled() async {
        installed = await store.installedRegions()
        storageByteCount = await store.storageByteCount()
    }

    private func setInstallPhase(_ phase: OfflineRegionInstallPhase, for regionID: String) {
        installPhases[regionID] = phase
    }
}
