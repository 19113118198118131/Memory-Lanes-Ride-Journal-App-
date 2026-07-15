import Foundation
import Testing
@testable import MemoryLanes

struct OfflineRoutingTelemetryTests {
    @Test func diagnosticsAggregateWithoutCoordinatesOrRouteGeometry() async throws {
        let suiteName = "offline-routing-telemetry-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let key = "diagnostics"
        let store = OfflineRoutingTelemetryStore(suiteName: suiteName, storageKey: key)

        await store.record(OfflineRoutingTelemetryEvent(
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            operation: .route,
            outcome: .localSuccess,
            regionID: "nz-auckland-north",
            regionName: "Auckland North",
            regionVersion: 1,
            durationMilliseconds: 321
        ))
        await store.record(OfflineRoutingTelemetryEvent(
            occurredAt: Date(timeIntervalSince1970: 1_700_000_100),
            operation: .anchorValidation,
            outcome: .fallback(.cannotSnap),
            regionID: "nz-auckland-north",
            regionName: "Auckland North",
            regionVersion: 1,
            durationMilliseconds: 42
        ))
        await store.record(OfflineRoutingTelemetryEvent(
            occurredAt: Date(timeIntervalSince1970: 1_700_000_200),
            operation: .route,
            outcome: .fallback(.noCoverage),
            regionID: nil,
            regionName: nil,
            regionVersion: nil,
            durationMilliseconds: 9
        ))
        await store.flush()

        let reloaded = OfflineRoutingTelemetryStore(suiteName: suiteName, storageKey: key)
        let diagnostics = await reloaded.diagnostics()
        #expect(diagnostics.localRouteCount == 1)
        #expect(diagnostics.localAnchorValidationCount == 0)
        #expect(diagnostics.fallbackCount == 1)
        #expect(diagnostics.fallbackCounts[.cannotSnap] == nil)
        #expect(diagnostics.fallbackCounts[.noCoverage] == 1)
        #expect(diagnostics.lastRegionID == "nz-auckland-north")
        #expect(diagnostics.lastRegionName == "Auckland North")
        #expect(diagnostics.lastRegionVersion == 1)
        #expect(diagnostics.lastFallbackReason == .noCoverage)
        #expect(diagnostics.lastDurationMilliseconds == 9)

        let persistedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let persisted = try #require(persistedDefaults.data(forKey: key))
        let text = String(decoding: persisted, as: UTF8.self)
        #expect(!text.contains("latitude"))
        #expect(!text.contains("longitude"))
        #expect(!text.contains("coordinates"))
    }

    @Test func resetRemovesPersistedDiagnostics() async throws {
        let suiteName = "offline-routing-telemetry-reset-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let store = OfflineRoutingTelemetryStore(suiteName: suiteName, storageKey: "diagnostics")
        await store.record(OfflineRoutingTelemetryEvent(
            occurredAt: Date(),
            operation: .route,
            outcome: .fallback(.noPath),
            regionID: nil,
            regionName: nil,
            regionVersion: nil,
            durationMilliseconds: 5
        ))

        await store.reset()

        #expect(await store.diagnostics() == .empty)
        #expect(UserDefaults(suiteName: suiteName)?.data(forKey: "diagnostics") == nil)
    }
}
