import Foundation
import CoreLocation
import Testing
@testable import MemoryLanes

struct PendingRideUploadTests {
    @Test func storePersistsMultipleRidesAndKeepsUsersSeparated() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstUser = UUID()
        let secondUser = UUID()
        let first = PendingRideUpload(
            title: "Morning loop",
            result: recordedRide(),
            plannedRouteID: nil,
            userID: firstUser
        )
        let second = PendingRideUpload(
            title: "Evening loop",
            result: recordedRide(),
            plannedRouteID: UUID(),
            userID: secondUser
        )
        let store = PendingRideUploadStore(directory: directory)

        try await store.save(first)
        try await store.save(second)

        #expect(await store.uploads(for: firstUser).map(\.id) == [first.id])
        #expect(await store.uploads(for: secondUser).map(\.id) == [second.id])
    }

    @Test func failureMetadataSurvivesStoreReload() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let userID = UUID()
        let upload = PendingRideUpload(
            title: "Coast ride",
            result: recordedRide(),
            plannedRouteID: nil,
            userID: userID
        )
        let store = PendingRideUploadStore(directory: directory)

        try await store.save(upload)
        try await store.markFailed(id: upload.id, errorDescription: "Offline")

        let reloaded = PendingRideUploadStore(directory: directory)
        let restored = await reloaded.uploads(for: userID).first
        #expect(restored?.attemptCount == 1)
        #expect(restored?.lastErrorDescription == "Offline")
        #expect(restored?.lastAttemptAt != nil)
    }

    @Test @MainActor func coordinatorRetainsFailureAndRetriesWithoutDuplicating() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingRideUploadStore(directory: directory)
        let uploader = StubRecordedRideUploader(fails: true)
        let coordinator = PendingRideUploadCoordinator(
            store: store,
            uploader: uploader,
            monitorsNetwork: false
        )
        let userID = UUID()
        let result = recordedRide()
        await coordinator.configure(userID: userID, accessToken: { "token" })

        let firstOutcome = try await coordinator.submit(
            title: "Queued ride",
            result: result,
            plannedRouteID: nil,
            userID: userID
        )

        #expect(firstOutcome == .queued)
        #expect(coordinator.pendingCount == 1)
        #expect(await uploader.attemptCount == 1)

        await uploader.setFails(false)
        await coordinator.sync()

        #expect(coordinator.pendingCount == 0)
        #expect(await uploader.attemptCount == 2)
        #expect(await store.uploads(for: userID).isEmpty)
    }

    private func recordedRide() -> RecordedRideResult {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            RecordingPoint(location: CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: -36.72, longitude: 174.74),
                altitude: 12,
                horizontalAccuracy: 4,
                verticalAccuracy: 5,
                course: 0,
                speed: 0,
                timestamp: startedAt
            )),
            RecordingPoint(location: CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: -36.719, longitude: 174.741),
                altitude: 14,
                horizontalAccuracy: 4,
                verticalAccuracy: 5,
                course: 45,
                speed: 10,
                timestamp: startedAt.addingTimeInterval(10)
            ))
        ]
        return RecordedRideResult(
            id: UUID(),
            title: "Recorded Ride",
            startedAt: startedAt,
            durationSeconds: 10,
            distanceMeters: 140,
            elevationGainMeters: 2,
            points: points,
            gpxText: "<gpx></gpx>"
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-upload-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor StubRecordedRideUploader: RecordedRideUploading {
    private var fails: Bool
    private(set) var attemptCount = 0

    init(fails: Bool) {
        self.fails = fails
    }

    func setFails(_ value: Bool) {
        fails = value
    }

    func saveRecordedRide(
        title: String,
        result: RecordedRideResult,
        plannedRouteID: UUID?,
        userID: UUID,
        accessToken: String
    ) async throws -> Ride {
        attemptCount += 1
        if fails { throw URLError(.notConnectedToInternet) }
        return Ride(
            id: result.id,
            title: title,
            date: result.startedAt,
            distanceMeters: result.distanceMeters,
            durationSeconds: result.durationSeconds,
            elevationGainMeters: result.elevationGainMeters,
            source: .live,
            routePreview: result.points.routePreview,
            gpxPath: "\(userID.uuidString)/\(result.id.uuidString).gpx",
            plannedRouteID: plannedRouteID
        )
    }
}
