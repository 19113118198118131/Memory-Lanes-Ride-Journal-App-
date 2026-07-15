import Foundation
import Testing
@testable import MemoryLanes

struct OfflineRoadRoutingTests {
    @Test func foundationInflatesCompilerDeflateContract() throws {
        let compilerBytes = Data([
            0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x57, 0xf0, 0x4d, 0xcd, 0xcd,
            0x2f, 0xaa, 0x54, 0xf0, 0x49, 0xcc, 0x4b, 0x2d, 0x06, 0x00
        ])
        let inflated = try (compilerBytes as NSData).decompressed(using: .zlib) as Data

        #expect(String(data: inflated, encoding: .utf8) == "hello Memory Lanes")
    }

    @Test func loaderInflatesDeflateAndBuildsSpatialIndex() async throws {
        let archive = TestRoadGraph.archive()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(archive)
        let compressed = try (payload as NSData).compressed(using: .zlib) as Data
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-graph-(UUID().uuidString).mlgraph")
        try compressed.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let graph = try await OfflineRoadGraphLoader().graph(at: url)
        let snap = graph.nearestNode(to: Coordinate(latitude: -36.80002, longitude: 174.70001))

        #expect(graph.coordinates.count == archive.nodes.count)
        #expect(graph.outgoingEdges.values.flatMap { $0 }.count == archive.edges.count)
        #expect(snap?.nodeID == 1)
        #expect((snap?.distanceMeters ?? .infinity) < 5)
    }

    @Test func pathfinderChoosesLowestTravelTime() throws {
        let graph = try OfflineRoadGraphIndex(archive: TestRoadGraph.archive())
        let path = try OfflineRoadPathfinder().path(in: graph, from: 1, to: 3)

        #expect(path.edges.map(\.wayID) == [10, 20])
        #expect(path.expectedTravelTime == 2)
    }

    @Test func nodeRestrictionRejectsOtherwiseShortestTurn() throws {
        let restriction = OfflineTurnRestriction(
            fromWayID: 10,
            viaNodeID: 2,
            viaWayIDs: [],
            toWayID: 20,
            kind: .prohibited,
            sourceTag: "no_left_turn",
            condition: nil
        )
        let graph = try OfflineRoadGraphIndex(archive: TestRoadGraph.archive(restrictions: [restriction]))
        let path = try OfflineRoadPathfinder().path(in: graph, from: 1, to: 3)

        #expect(path.edges.map(\.wayID) == [10, 30, 40])
    }

    @Test func wayRestrictionCarriesHistoryAcrossIntermediateRoad() throws {
        let restriction = OfflineTurnRestriction(
            fromWayID: 10,
            viaNodeID: nil,
            viaWayIDs: [30],
            toWayID: 40,
            kind: .prohibited,
            sourceTag: "no_straight_on",
            condition: nil
        )
        let graph = try OfflineRoadGraphIndex(archive: TestRoadGraph.archive(
            edges: [
                TestRoadGraph.edge(way: 10, from: 1, to: 2, seconds: 1),
                TestRoadGraph.edge(way: 30, from: 2, to: 4, seconds: 1),
                TestRoadGraph.edge(way: 40, from: 4, to: 3, seconds: 1),
                TestRoadGraph.edge(way: 50, from: 4, to: 5, seconds: 2),
                TestRoadGraph.edge(way: 60, from: 5, to: 3, seconds: 2)
            ],
            restrictions: [restriction]
        ))
        let path = try OfflineRoadPathfinder().path(in: graph, from: 1, to: 3)

        #expect(path.edges.map(\.wayID) == [10, 30, 50, 60])
    }

    @Test func oneWayEdgeCannotBeTraversedBackwards() throws {
        let archive = TestRoadGraph.archive(edges: [TestRoadGraph.edge(way: 10, from: 1, to: 2, seconds: 1)])
        let graph = try OfflineRoadGraphIndex(archive: archive)

        #expect(throws: OfflineRoadRoutingError.noPath) {
            _ = try OfflineRoadPathfinder().path(in: graph, from: 2, to: 1)
        }
    }

    @Test func providerSnapsWaypointsAndAddsRoadContext() async throws {
        let archive = TestRoadGraph.archive(edges: [
            TestRoadGraph.edge(way: 10, from: 1, to: 2, seconds: 1, roadClass: .motorway),
            TestRoadGraph.edge(way: 20, from: 2, to: 3, seconds: 1, surface: "gravel")
        ])
        let graph = try OfflineRoadGraphIndex(archive: archive)
        let telemetry = RecordingOfflineRoutingTelemetry()
        let provider = OfflineRoadRouteProvider(
            regionStore: StubOfflineRegionStore(url: URL(fileURLWithPath: "/tmp/test.mlgraph")),
            graphLoader: StubOfflineGraphLoader(graph: graph),
            telemetry: telemetry
        )

        let route = try await provider.route(through: [
            Coordinate(latitude: -36.80001, longitude: 174.70001),
            Coordinate(latitude: -36.79801, longitude: 174.70201)
        ])

        #expect(route.coordinates.map(\.latitude) == [-36.8, -36.799, -36.798])
        #expect(route.context.motorwayRatio == 0.5)
        #expect(route.context.unsuitableSurfaceRatio == 0.5)
        let event = await telemetry.events.first
        #expect(event?.operation == .route)
        #expect(event?.outcome == .localSuccess)
        #expect(event?.regionID == "test-region")
        #expect(event?.regionVersion == 3)
    }

    @Test func providerChoosesTheClosestComponentSharedByEveryWaypoint() async throws {
        let archive = OfflineRoadGraphArchive(
            formatVersion: 1,
            regionID: "component-test",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            bounds: OfflineRegionBounds(south: -37, west: 174, north: -36, east: 175),
            attribution: "OpenStreetMap contributors",
            nodes: [
                OfflineRoadNode(id: 1, coordinate: Coordinate(latitude: -36.800, longitude: 174.701)),
                OfflineRoadNode(id: 2, coordinate: Coordinate(latitude: -36.795, longitude: 174.705)),
                OfflineRoadNode(id: 3, coordinate: Coordinate(latitude: -36.790, longitude: 174.710)),
                OfflineRoadNode(id: 6, coordinate: Coordinate(latitude: -36.800, longitude: 174.700)),
                OfflineRoadNode(id: 7, coordinate: Coordinate(latitude: -36.8001, longitude: 174.7001))
            ],
            edges: [
                TestRoadGraph.edge(way: 10, from: 1, to: 2, seconds: 1),
                TestRoadGraph.edge(way: 20, from: 2, to: 3, seconds: 1),
                TestRoadGraph.edge(way: 60, from: 6, to: 7, seconds: 1),
                TestRoadGraph.edge(way: 60, from: 7, to: 6, seconds: 1)
            ],
            turnRestrictions: []
        )
        let graph = try OfflineRoadGraphIndex(archive: archive)
        let provider = OfflineRoadRouteProvider(
            regionStore: StubOfflineRegionStore(url: URL(fileURLWithPath: "/tmp/component-test.mlgraph")),
            graphLoader: StubOfflineGraphLoader(graph: graph),
            telemetry: RecordingOfflineRoutingTelemetry()
        )

        let route = try await provider.route(through: [
            Coordinate(latitude: -36.800, longitude: 174.700),
            Coordinate(latitude: -36.790, longitude: 174.710)
        ])

        #expect(route.coordinates.count == 3)
        #expect(route.coordinates.first?.longitude == 174.701)
        #expect(route.coordinates.last?.longitude == 174.710)
    }

    @Test func offlineFirstProviderFallsBackWhenCoverageIsMissing() async throws {
        let fallbackRoute = RoadRoute(
            coordinates: TestRoadGraph.coordinates.values.sorted { $0.latitude < $1.latitude },
            distanceMeters: 42,
            expectedTravelTime: 7,
            context: .geometryOnly
        )
        let provider = OfflineFirstRoadRouteProvider(
            offline: ThrowingRoadProvider(error: OfflineRoadRoutingError.noCoverage),
            fallback: FixedRoadProvider(route: fallbackRoute)
        )

        let route = try await provider.route(through: Array(fallbackRoute.coordinates.prefix(2)))
        #expect(route == fallbackRoute)
    }

    @Test func providerRecordsCoordinateFreeFallbackReason() async throws {
        let telemetry = RecordingOfflineRoutingTelemetry()
        let provider = OfflineRoadRouteProvider(
            regionStore: MissingOfflineRegionStore(),
            graphLoader: StubOfflineGraphLoader(graph: try OfflineRoadGraphIndex(archive: TestRoadGraph.archive())),
            telemetry: telemetry
        )

        await #expect(throws: OfflineRoadRoutingError.noCoverage) {
            _ = try await provider.route(through: [
                Coordinate(latitude: -36.8, longitude: 174.7),
                Coordinate(latitude: -36.7, longitude: 174.8)
            ])
        }

        let event = await telemetry.events.first
        #expect(event?.outcome == .fallback(.noCoverage))
        #expect(event?.regionID == nil)
        #expect(event?.regionName == nil)
        #expect(event?.regionVersion == nil)
    }
}

private enum TestRoadGraph {
    static let coordinates: [UInt64: Coordinate] = [
        1: Coordinate(latitude: -36.800, longitude: 174.700),
        2: Coordinate(latitude: -36.799, longitude: 174.701),
        3: Coordinate(latitude: -36.798, longitude: 174.702),
        4: Coordinate(latitude: -36.7985, longitude: 174.701),
        5: Coordinate(latitude: -36.7982, longitude: 174.7015)
    ]

    static func archive(
        edges: [OfflineRoadEdge]? = nil,
        restrictions: [OfflineTurnRestriction] = []
    ) -> OfflineRoadGraphArchive {
        OfflineRoadGraphArchive(
            formatVersion: 1,
            regionID: "test-region",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            bounds: OfflineRegionBounds(south: -37, west: 174, north: -36, east: 175),
            attribution: "OpenStreetMap contributors",
            nodes: coordinates.map { OfflineRoadNode(id: $0.key, coordinate: $0.value) },
            edges: edges ?? [
                edge(way: 10, from: 1, to: 2, seconds: 1),
                edge(way: 20, from: 2, to: 3, seconds: 1),
                edge(way: 30, from: 2, to: 4, seconds: 2),
                edge(way: 40, from: 4, to: 3, seconds: 2),
                edge(way: 50, from: 4, to: 5, seconds: 2),
                edge(way: 60, from: 5, to: 3, seconds: 2)
            ],
            turnRestrictions: restrictions
        )
    }

    static func edge(
        way: UInt64,
        from source: UInt64,
        to destination: UInt64,
        seconds: TimeInterval,
        roadClass: OfflineRoadClass = .secondary,
        surface: String? = "asphalt"
    ) -> OfflineRoadEdge {
        OfflineRoadEdge(
            wayID: way,
            sourceNodeID: source,
            destinationNodeID: destination,
            distanceMeters: 100,
            expectedTravelTime: seconds,
            roadClass: roadClass,
            name: nil,
            surface: surface,
            maximumSpeedKPH: nil
        )
    }
}

private struct StubOfflineRegionStore: OfflineRegionServing {
    let url: URL

    func catalog(forceRefresh _: Bool) async throws -> OfflineRegionManifest {
        throw OfflineRoadRoutingError.noCoverage
    }

    func installedRegions() async -> [InstalledOfflineRegion] { [] }

    func install(
        _: OfflineRegionDescriptor,
        wifiOnly _: Bool,
        progress _: @Sendable @escaping (OfflineRegionInstallPhase) async -> Void
    ) async throws -> InstalledOfflineRegion {
        throw OfflineRoadRoutingError.noCoverage
    }

    func remove(regionID _: String) async throws {}
    func storageByteCount() async -> Int64 { 0 }
    func localGraph(containing _: Coordinate) async -> InstalledOfflineRoadGraph? {
        InstalledOfflineRoadGraph(
            regionID: "test-region",
            regionName: "Test Region",
            version: 3,
            fileURL: url
        )
    }
}

private struct MissingOfflineRegionStore: OfflineRegionServing {
    func catalog(forceRefresh _: Bool) async throws -> OfflineRegionManifest {
        throw OfflineRoadRoutingError.noCoverage
    }

    func installedRegions() async -> [InstalledOfflineRegion] { [] }

    func install(
        _: OfflineRegionDescriptor,
        wifiOnly _: Bool,
        progress _: @Sendable @escaping (OfflineRegionInstallPhase) async -> Void
    ) async throws -> InstalledOfflineRegion {
        throw OfflineRoadRoutingError.noCoverage
    }

    func remove(regionID _: String) async throws {}
    func storageByteCount() async -> Int64 { 0 }
    func localGraph(containing _: Coordinate) async -> InstalledOfflineRoadGraph? { nil }
}

private struct StubOfflineGraphLoader: OfflineRoadGraphLoading {
    let graph: OfflineRoadGraphIndex
    func graph(at _: URL) async throws -> OfflineRoadGraphIndex { graph }
}

private struct ThrowingRoadProvider: RoadRouteProviding {
    let error: any Error & Sendable
    func route(through _: [Coordinate]) async throws -> RoadRoute { throw error }
}

private struct FixedRoadProvider: RoadRouteProviding {
    let route: RoadRoute
    func route(through _: [Coordinate]) async throws -> RoadRoute { route }
}

private actor RecordingOfflineRoutingTelemetry: OfflineRoutingTelemetryServing {
    private(set) var events: [OfflineRoutingTelemetryEvent] = []

    func record(_ event: OfflineRoutingTelemetryEvent) {
        events.append(event)
    }

    func diagnostics() -> OfflineRoutingDiagnostics { .empty }
    func reset() { events = [] }
}
