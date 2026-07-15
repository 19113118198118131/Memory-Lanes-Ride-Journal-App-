import Foundation

enum OfflineRoutingOperation: String, Codable, Sendable {
    case anchorValidation
    case route
}

enum OfflineRoutingFallbackReason: String, Codable, CaseIterable, Sendable {
    case noCoverage
    case invalidArchive
    case cannotSnap
    case noPath
    case searchLimitReached
    case unexpected

    init(error: any Error) {
        switch error as? OfflineRoadRoutingError {
        case .noCoverage: self = .noCoverage
        case .invalidArchive: self = .invalidArchive
        case .cannotSnap: self = .cannotSnap
        case .noPath: self = .noPath
        case .searchLimitReached: self = .searchLimitReached
        case nil: self = .unexpected
        }
    }

    var title: String {
        switch self {
        case .noCoverage: "Outside downloaded area"
        case .invalidArchive: "Road pack unavailable"
        case .cannotSnap: "Road match unavailable"
        case .noPath: "No connected local path"
        case .searchLimitReached: "Route exceeded device limit"
        case .unexpected: "Local routing unavailable"
        }
    }
}

struct OfflineRoutingTelemetryEvent: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case localSuccess
        case fallback(OfflineRoutingFallbackReason)
    }

    let occurredAt: Date
    let operation: OfflineRoutingOperation
    let outcome: Outcome
    let regionID: String?
    let regionName: String?
    let regionVersion: Int?
    let durationMilliseconds: Int
}

struct OfflineRoutingDiagnostics: Codable, Equatable, Sendable {
    static let empty = OfflineRoutingDiagnostics(
        localRouteCount: 0,
        localAnchorValidationCount: 0,
        fallbackCounts: [:],
        lastAttemptAt: nil,
        lastRegionID: nil,
        lastRegionName: nil,
        lastRegionVersion: nil,
        lastFallbackReason: nil,
        lastDurationMilliseconds: nil
    )

    var localRouteCount: Int
    var localAnchorValidationCount: Int
    var fallbackCounts: [OfflineRoutingFallbackReason: Int]
    var lastAttemptAt: Date?
    var lastRegionID: String?
    var lastRegionName: String?
    var lastRegionVersion: Int?
    var lastFallbackReason: OfflineRoutingFallbackReason?
    var lastDurationMilliseconds: Int?

    var fallbackCount: Int {
        fallbackCounts.values.reduce(0, +)
    }
}

protocol OfflineRoutingTelemetryServing: Sendable {
    func record(_ event: OfflineRoutingTelemetryEvent) async
    func diagnostics() async -> OfflineRoutingDiagnostics
    func reset() async
}

actor OfflineRoutingTelemetryStore: OfflineRoutingTelemetryServing {
    static let shared = OfflineRoutingTelemetryStore()

    private let defaults: UserDefaults
    private let storageKey: String
    private var cached: OfflineRoutingDiagnostics?
    private var pendingPersistence: Task<Void, Never>?

    init(
        suiteName: String? = nil,
        storageKey: String = "offlineRouting.diagnostics.v1"
    ) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.storageKey = storageKey
    }

    func record(_ event: OfflineRoutingTelemetryEvent) {
        var value = load()
        switch event.outcome {
        case .localSuccess:
            if event.operation == .route {
                value.localRouteCount += 1
            } else {
                value.localAnchorValidationCount += 1
            }
            value.lastFallbackReason = nil
        case .fallback(let reason):
            if event.operation == .route {
                value.fallbackCounts[reason, default: 0] += 1
            }
            value.lastFallbackReason = reason
        }
        value.lastAttemptAt = event.occurredAt
        if event.regionID != nil {
            value.lastRegionID = event.regionID
            value.lastRegionName = event.regionName
            value.lastRegionVersion = event.regionVersion
        }
        value.lastDurationMilliseconds = max(event.durationMilliseconds, 0)
        cached = value
        schedulePersistence()
    }

    func diagnostics() -> OfflineRoutingDiagnostics {
        load()
    }

    func reset() {
        pendingPersistence?.cancel()
        pendingPersistence = nil
        cached = .empty
        defaults.removeObject(forKey: storageKey)
    }

    func flush() {
        pendingPersistence?.cancel()
        pendingPersistence = nil
        persistCachedValue()
    }

    private func load() -> OfflineRoutingDiagnostics {
        if let cached { return cached }
        guard let data = defaults.data(forKey: storageKey),
              let value = try? Self.decoder.decode(OfflineRoutingDiagnostics.self, from: data) else {
            cached = .empty
            return .empty
        }
        cached = value
        return value
    }

    private func schedulePersistence() {
        pendingPersistence?.cancel()
        pendingPersistence = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.persistCachedValue()
        }
    }

    private func persistCachedValue() {
        guard let value = cached else { return }
        guard let data = try? Self.encoder.encode(value) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
