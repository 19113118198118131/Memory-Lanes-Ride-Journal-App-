import CoreLocation
import XCTest
@testable import MemoryLanes

final class GroupLiveLocationTests: XCTestCase {
    func testLiveRiderDecodesSupabaseContract() throws {
        let json = """
        [{
          "id": "7a39b877-5a4d-4a38-a959-a4a80144911d",
          "name": "Alex",
          "lat": -36.71,
          "lng": 174.74,
          "speed_kmh": 42.5,
          "updated_at": "2026-07-16T06:00:00.123456+00:00"
        }]
        """

        let riders = try JSONDecoder.supabase.decode(
            [GroupLiveRider].self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(riders.first?.name, "Alex")
        XCTAssertEqual(riders.first?.id.uuidString.lowercased(), "7a39b877-5a4d-4a38-a959-a4a80144911d")
        XCTAssertEqual(riders.first?.latitude, -36.71)
        XCTAssertEqual(riders.first?.speedKmH, 42.5)
    }

    func testPublisherThrottlesRapidPositionUpdates() async throws {
        let service = GroupLiveLocationServiceSpy()
        let token = UUID()
        let publisher = GroupLivePositionPublisher(
            service: service,
            shareToken: token,
            minimumInterval: 10
        )
        let point = makePoint()
        let start = Date(timeIntervalSince1970: 1_000)

        let first = try await publisher.offer(point, now: start)
        let throttled = try await publisher.offer(point, now: start.addingTimeInterval(9))
        let second = try await publisher.offer(point, now: start.addingTimeInterval(10))

        XCTAssertTrue(first)
        XCTAssertFalse(throttled)
        XCTAssertTrue(second)
        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.publishedTokens, [token, token])
    }

    @MainActor
    func testControllerRequiresExplicitChoiceBeforePublishingButStillLoadsGroupMap() async {
        let service = GroupLiveLocationServiceSpy()
        let context = GroupRideRecordingContext(
            shareToken: UUID(),
            title: "Sunday Loop",
            shareLiveLocation: false
        )
        let controller = GroupLiveSharingController(context: context, service: service)

        await controller.start()
        await controller.offer(makePoint())

        XCTAssertEqual(controller.status, .unavailable)
        XCTAssertTrue(controller.isVisible)
        let snapshot = await service.snapshot()
        XCTAssertTrue(snapshot.sharingChanges.isEmpty)
        XCTAssertTrue(snapshot.publishedTokens.isEmpty)
        XCTAssertEqual(snapshot.fetchCount, 1)
    }

    @MainActor
    func testControllerStopsSharingWithoutAffectingRecordingData() async {
        let service = GroupLiveLocationServiceSpy()
        let token = UUID()
        let context = GroupRideRecordingContext(
            shareToken: token,
            title: "Sunday Loop",
            shareLiveLocation: true
        )
        let controller = GroupLiveSharingController(context: context, service: service)
        let point = makePoint()

        await controller.start()
        await controller.offer(point)
        await controller.stop()

        XCTAssertEqual(controller.status, .stopped)
        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.sharingChanges.map(\.enabled), [true, false])
        XCTAssertEqual(snapshot.publishedTokens, [token])
        XCTAssertEqual(point.coordinate, Coordinate(latitude: -36.71, longitude: 174.74))
    }

    @MainActor
    func testControllerRemovesStaleRidersWhenRefreshFails() async {
        let service = GroupLiveLocationServiceSpy()
        let now = Date(timeIntervalSince1970: 2_000)
        await service.setRiders([
            GroupLiveRider(
                id: UUID(),
                name: "Alex",
                latitude: -36.71,
                longitude: 174.74,
                speedKmH: 42,
                updatedAt: now.addingTimeInterval(-30)
            )
        ])
        let controller = GroupLiveSharingController(
            context: GroupRideRecordingContext(
                shareToken: UUID(),
                title: "Sunday Loop",
                shareLiveLocation: false
            ),
            service: service
        )

        await controller.refreshRiders(now: now)
        XCTAssertEqual(controller.riders.count, 1)

        await service.setFetchError(true)
        await controller.refreshRiders(now: now.addingTimeInterval(121))

        XCTAssertTrue(controller.riders.isEmpty)
        XCTAssertEqual(controller.riderMapStatus, .offline)
    }

    private func makePoint() -> RecordingPoint {
        RecordingPoint(location: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -36.71, longitude: 174.74),
            altitude: 42,
            horizontalAccuracy: 5,
            verticalAccuracy: 7,
            course: 18,
            speed: 12,
            timestamp: Date(timeIntervalSince1970: 1_000)
        ))
    }
}

private actor GroupLiveLocationServiceSpy: GroupLiveLocationServing {
    struct SharingChange: Sendable {
        let enabled: Bool
        let token: UUID
    }

    struct Snapshot: Sendable {
        let sharingChanges: [SharingChange]
        let publishedTokens: [UUID]
        let fetchCount: Int
    }

    private var sharingChanges: [SharingChange] = []
    private var publishedTokens: [UUID] = []
    private var riders: [GroupLiveRider] = []
    private var fetchCount = 0
    private var shouldFailFetch = false

    func setSharing(_ enabled: Bool, shareToken: UUID) async throws -> GroupLiveSharingReceipt {
        sharingChanges.append(SharingChange(enabled: enabled, token: shareToken))
        return GroupLiveSharingReceipt(
            enabled: enabled,
            expiresAt: enabled ? Date(timeIntervalSince1970: 44_200) : nil
        )
    }

    func publish(_ point: RecordingPoint, shareToken: UUID) async throws {
        publishedTokens.append(shareToken)
    }

    func fetchRiders(shareToken: UUID) async throws -> [GroupLiveRider] {
        fetchCount += 1
        if shouldFailFetch { throw GroupLiveLocationError.publishRejected }
        return riders
    }

    func setRiders(_ riders: [GroupLiveRider]) {
        self.riders = riders
    }

    func setFetchError(_ shouldFail: Bool) {
        shouldFailFetch = shouldFail
    }

    func snapshot() -> Snapshot {
        Snapshot(
            sharingChanges: sharingChanges,
            publishedTokens: publishedTokens,
            fetchCount: fetchCount
        )
    }
}
