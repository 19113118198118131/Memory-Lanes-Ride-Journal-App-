import Foundation
import Observation

enum OfflineAreaDownloadStage: Equatable {
    case map
    case routing(String)
    case finalizing

    var title: String {
        switch self {
        case .map: "Downloading map"
        case .routing: "Adding offline routes"
        case .finalizing: "Finishing offline area"
        }
    }

    var detail: String {
        switch self {
        case .map: "Map detail, labels and places"
        case .routing(let name): "Route planning and turn-by-turn for \(name)"
        case .finalizing: "Checking everything is ready"
        }
    }
}

struct OfflineAreaCapability: Equatable {
    enum Level: Equatable {
        case mapOnly
        case setupAvailable
        case partial
        case complete
    }

    let level: Level
    let installedCoverage: Double
    let publishedCoverage: Double

    var title: String {
        switch level {
        case .mapOnly: "Map ready offline"
        case .setupAvailable: "Routes ready to add"
        case .partial: "Map + local routes ready"
        case .complete: "Map + navigation ready"
        }
    }

    var detail: String {
        switch level {
        case .mapOnly:
            "The map works offline. Route data has not been published here yet."
        case .setupAvailable:
            "Finish setup to add local route planning and turn-by-turn."
        case .partial:
            "Route planning and navigation work inside the downloaded road coverage."
        case .complete:
            "Generate routes and navigate without reception throughout this area."
        }
    }
}

@MainActor
@Observable
final class OfflineAreasViewModel {
    private(set) var mapAreas: [OfflineMapArea] = []
    private(set) var mapDownloadProgress: OfflineMapDownloadProgress?
    private(set) var isDownloadingMap = false
    private(set) var downloadStage: OfflineAreaDownloadStage = .map
    private(set) var areasCompletingSetup: Set<UUID> = []
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
    private let mapStore: any OfflineMapServing
    private let routingTelemetry: any OfflineRoutingTelemetryServing
    private let defaults: UserDefaults
    private static let wifiOnlyKey = "offlineAreas.wifiOnly"

    init(
        store: any OfflineRegionServing = OfflineRegionStore.shared,
        mapStore: any OfflineMapServing = MapLibreOfflineMapStore.shared,
        routingTelemetry: any OfflineRoutingTelemetryServing = OfflineRoutingTelemetryStore.shared,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.mapStore = mapStore
        self.routingTelemetry = routingTelemetry
        self.defaults = defaults
        self.wifiOnly = defaults.object(forKey: Self.wifiOnlyKey) as? Bool ?? true
    }

    var available: [OfflineRegionDescriptor] {
        catalog.sorted { $0.name < $1.name }
    }

    var storageText: String {
        let mapBytes = mapAreas.reduce(Int64(0)) { $0 + $1.bytesDownloaded }
        return ByteCountFormatter.string(fromByteCount: mapBytes + storageByteCount, countStyle: .file)
    }

    var readinessText: String {
        let readyCount = mapAreas.filter { $0.status == .complete }.count
        return switch readyCount {
        case 0: "No offline areas"
        case 1: "1 area ready"
        default: "\(readyCount) areas ready"
        }
    }

    var activeMapDownloadCount: Int {
        mapAreas.filter { $0.status == .downloading || $0.status == .preparing }.count
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
        mapAreas = await mapStore.areas()
        isLoading = false
    }

    func downloadMap(name: String, draft: OfflineMapAreaDraft) async -> Bool {
        guard !isDownloadingMap else { return false }
        isDownloadingMap = true
        downloadStage = .map
        mapDownloadProgress = OfflineMapDownloadProgress(fractionCompleted: 0, bytesCompleted: 0)
        do {
            _ = try await mapStore.download(name: name, draft: draft) { [weak self] progress in
                self?.mapDownloadProgress = progress
            }
            mapAreas = await mapStore.areas()
            let routingRegions = regions(intersecting: draft.bounds)
            var routingReady = true
            for region in routingRegions where !isCurrent(region) {
                downloadStage = .routing(region.name)
                if !(await installRegion(region, presentsFeedback: false)) {
                    routingReady = false
                }
            }
            downloadStage = .finalizing
            await refreshInstalled()
            mapDownloadProgress = nil
            isDownloadingMap = false
            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if routingRegions.isEmpty {
                Haptics.warning()
                toast = .info("\(normalizedName) map is ready. Offline routes are not published there yet.")
            } else if routingReady {
                Haptics.success()
                toast = .success("\(normalizedName) is ready for maps, routes and navigation")
            } else {
                Haptics.warning()
                toast = .info("\(normalizedName) map is ready. Finish offline route setup when connected.")
            }
            return true
        } catch is CancellationError {
            mapAreas = await mapStore.areas()
            mapDownloadProgress = nil
            isDownloadingMap = false
            return false
        } catch {
            mapAreas = await mapStore.areas()
            mapDownloadProgress = nil
            isDownloadingMap = false
            Haptics.error()
            toast = .error(error.localizedDescription)
            return false
        }
    }

    func resumeMapArea(_ area: OfflineMapArea) async {
        do {
            try await mapStore.resume(areaID: area.id)
            mapAreas = await mapStore.areas()
            toast = .success("\(area.name) download resumed")
        } catch {
            Haptics.error()
            toast = .error(error.localizedDescription)
        }
    }

    func refreshMapAreas() async {
        mapAreas = await mapStore.areas()
    }

    func renameMapArea(_ area: OfflineMapArea, to name: String) async {
        do {
            try await mapStore.rename(areaID: area.id, name: name)
            mapAreas = await mapStore.areas()
            Haptics.success()
            toast = .success("Offline area renamed")
        } catch {
            Haptics.error()
            toast = .error(error.localizedDescription)
        }
    }

    func removeMapArea(_ area: OfflineMapArea) async {
        do {
            try await mapStore.remove(areaID: area.id)
            mapAreas = await mapStore.areas()
            await removeUnreferencedRoutingData(associatedWith: area)
            Haptics.success()
            toast = .success("\(area.name) removed")
        } catch {
            Haptics.error()
            toast = .error(error.localizedDescription)
        }
    }

    func completeOfflineSetup(for area: OfflineMapArea) async {
        guard !areasCompletingSetup.contains(area.id) else { return }
        let regions = regions(intersecting: area.bounds).filter { !isCurrent($0) }
        guard !regions.isEmpty else {
            toast = .info("No additional offline route data is available for this area yet.")
            return
        }
        areasCompletingSetup.insert(area.id)
        var completed = true
        for region in regions {
            if !(await installRegion(region, presentsFeedback: false)) { completed = false }
        }
        areasCompletingSetup.remove(area.id)
        await refreshInstalled()
        if completed {
            Haptics.success()
            toast = .success("\(area.name) is ready for offline route planning and navigation")
        } else {
            Haptics.error()
            toast = .error("Some route data could not be downloaded. Try again when connected.")
        }
    }

    func isCompletingSetup(for area: OfflineMapArea) -> Bool {
        areasCompletingSetup.contains(area.id)
    }

    func needsRoutingSetup(for area: OfflineMapArea) -> Bool {
        regions(intersecting: area.bounds).contains { !isCurrent($0) }
    }

    func capability(for area: OfflineMapArea) -> OfflineAreaCapability {
        let published = coverageFraction(for: area.bounds)
        let installed = installedCoverageFraction(for: area.bounds)
        let level: OfflineAreaCapability.Level
        if installed >= 0.9 {
            level = .complete
        } else if installed > 0.001 {
            level = .partial
        } else if published > 0.001 {
            level = .setupAvailable
        } else {
            level = .mapOnly
        }
        return OfflineAreaCapability(
            level: level,
            installedCoverage: installed,
            publishedCoverage: published
        )
    }

    func estimatedDownloadSizeText(for draft: OfflineMapAreaDraft) -> String {
        let routingBytes = regions(intersecting: draft.bounds)
            .filter { !isCurrent($0) }
            .reduce(Int64(0)) { $0 + $1.byteCount }
        return ByteCountFormatter.string(
            fromByteCount: draft.estimatedByteCount + routingBytes,
            countStyle: .file
        )
    }

    private func installRegion(
        _ region: OfflineRegionDescriptor,
        presentsFeedback: Bool
    ) async -> Bool {
        guard installPhases[region.id] == nil else { return false }
        installPhases[region.id] = .downloading
        do {
            _ = try await store.install(region, wifiOnly: wifiOnly) { [weak self] phase in
                await self?.setInstallPhase(phase, for: region.id)
            }
            installPhases[region.id] = nil
            await refreshInstalled()
            if presentsFeedback {
                Haptics.success()
                toast = .success("\(region.name) is ready offline")
            }
            return true
        } catch is CancellationError {
            installPhases[region.id] = nil
            return false
        } catch {
            installPhases[region.id] = nil
            if presentsFeedback {
                Haptics.error()
                toast = .error(error.localizedDescription)
            }
            return false
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

    func coverageFraction(for bounds: OfflineRegionBounds) -> Double {
        bounds.coverageFraction(by: regions(intersecting: bounds).map(\.bounds))
    }

    func installedCoverageFraction(for bounds: OfflineRegionBounds) -> Double {
        bounds.coverageFraction(by: installed.map(\.descriptor.bounds))
    }

    func nearestAvailableRegion(to coordinate: Coordinate) -> OfflineRegionDescriptor? {
        available.min { first, second in
            squaredDistance(from: coordinate, to: first.bounds.center)
                < squaredDistance(from: coordinate, to: second.bounds.center)
        }
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

    private func removeUnreferencedRoutingData(associatedWith removedArea: OfflineMapArea) async {
        let candidates = installed.filter { $0.descriptor.bounds.intersects(removedArea.bounds) }
        for region in candidates {
            let isStillUsed = mapAreas.contains { $0.bounds.intersects(region.descriptor.bounds) }
            if !isStillUsed {
                try? await store.remove(regionID: region.id)
            }
        }
        await refreshInstalled()
    }

    private func setInstallPhase(_ phase: OfflineRegionInstallPhase, for regionID: String) {
        installPhases[regionID] = phase
    }

    private func squaredDistance(from first: Coordinate, to second: Coordinate) -> Double {
        let latitude = (first.latitude + second.latitude) * .pi / 360
        let longitudeScale = cos(latitude)
        let latitudeDelta = first.latitude - second.latitude
        let longitudeDelta = (first.longitude - second.longitude) * longitudeScale
        return latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta
    }
}
