import CoreLocation
import Foundation
import XCTest
@testable import MemoryLanes

final class RideLocalStoreTests: XCTestCase {
    func testRideAndGPXPersistAcrossStoreInstancesAndAccountsStayIsolated() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ride-local-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let userID = UUID()
        let otherUserID = UUID()
        let ride = makeRide(source: .live)
        let data = makeGPXData()
        let journalEntry = JournalEntry(
            id: "entry-1",
            title: "A good corner",
            note: "Smooth and settled",
            ride: ride,
            rideDate: ride.date,
            index: 0,
            coordinate: ride.routePreview.first,
            speedKmh: 48,
            elevationMeters: 32
        )
        let firstStore = RideLocalStore(rootURL: root)
        try await firstStore.upsert(ride, gpxData: data, for: userID)
        try await firstStore.replaceJournalEntries([journalEntry], for: userID)

        let secondStore = RideLocalStore(rootURL: root)
        let cachedRides = await secondStore.rides(for: userID)
        let cachedData = await secondStore.gpxData(for: ride, userID: userID)
        let cachedJournal = await secondStore.journalEntries(for: userID)
        let otherRides = await secondStore.rides(for: otherUserID)

        XCTAssertEqual(cachedRides.count, 1)
        XCTAssertEqual(cachedRides.first?.title, ride.title)
        XCTAssertEqual(cachedRides.first?.source, .live)
        XCTAssertEqual(cachedRides.first?.routePreview, ride.routePreview)
        XCTAssertEqual(cachedData, data)
        XCTAssertEqual(cachedJournal.map(\.id), [journalEntry.id])
        XCTAssertEqual(cachedJournal.first?.note, journalEntry.note)
        XCTAssertTrue(otherRides.isEmpty)
    }

    func testRemoteRefreshPreservesLocalTrackAndChangedPathInvalidatesIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ride-local-refresh-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let userID = UUID()
        let localRide = makeRide(source: .live)
        let data = makeGPXData()
        let track = try GPXParser().parse(data: data)
        let store = RideLocalStore(rootURL: root)
        try await store.upsert(localRide, gpxData: data, for: userID)
        try await store.storeParsedTrack(track, for: localRide, userID: userID)
        let detail = RideDetail(
            id: localRide.id,
            routePreview: track.routePreview,
            replayPoints: track.replayPoints,
            elevation: track.elevationSamples,
            corners: [],
            moments: [],
            weather: nil,
            coachScore: 72,
            coachScores: [],
            debrief: "Cached analysis"
        )
        try await store.storeDetail(detail, for: localRide, userID: userID, analysisVersion: 1)

        var refreshedRide = localRide
        refreshedRide.title = "Cloud title"
        refreshedRide.source = .gpx
        refreshedRide.routePreview = []
        let refreshed = try await store.replaceRides([refreshedRide], for: userID)
        let preservedData = await store.gpxData(for: refreshedRide, userID: userID)
        let preservedTrack = await store.parsedTrack(for: refreshedRide, userID: userID)
        let preservedDetail = await store.detail(for: refreshedRide, userID: userID, analysisVersion: 1)

        XCTAssertEqual(refreshed.first?.title, "Cloud title")
        XCTAssertEqual(refreshed.first?.source, .live)
        XCTAssertEqual(refreshed.first?.routePreview, localRide.routePreview)
        XCTAssertNotNil(preservedData)
        XCTAssertNotNil(preservedTrack)
        XCTAssertEqual(preservedDetail?.coachScore, 72)
        XCTAssertEqual(preservedDetail?.debrief, "Cached analysis")

        var changedTrack = refreshedRide
        changedTrack.gpxPath = "user/replaced.gpx"
        _ = try await store.replaceRides([changedTrack], for: userID)
        let invalidatedData = await store.gpxData(for: changedTrack, userID: userID)
        let invalidatedTrack = await store.parsedTrack(for: changedTrack, userID: userID)
        let invalidatedDetail = await store.detail(for: changedTrack, userID: userID, analysisVersion: 1)

        XCTAssertNil(invalidatedData)
        XCTAssertNil(invalidatedTrack)
        XCTAssertNil(invalidatedDetail)
    }

    private func makeRide(source: RideSource) -> Ride {
        Ride(
            title: "Cached ride",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMeters: 12_300,
            durationSeconds: 1_800,
            elevationGainMeters: 240,
            source: source,
            routePreview: [
                Coordinate(latitude: -36.84, longitude: 174.76),
                Coordinate(latitude: -36.83, longitude: 174.78)
            ],
            gpxPath: "user/track.gpx"
        )
    }

    private func makeGPXData() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Memory Lanes" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="-36.8400" lon="174.7600"><ele>20</ele><time>2026-07-15T00:00:00Z</time></trkpt>
            <trkpt lat="-36.8300" lon="174.7800"><ele>24</ele><time>2026-07-15T00:00:01Z</time></trkpt>
          </trkseg></trk>
        </gpx>
        """.utf8)
    }
}
