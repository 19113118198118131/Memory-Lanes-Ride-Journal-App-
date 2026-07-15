import XCTest
@testable import MemoryLanes

final class GroupRideTests: XCTestCase {
    func testGroupRidePayloadDecodesOriginalWebContract() throws {
        let groupID = UUID()
        let routeID = UUID()
        let token = UUID()
        let json = """
        {
          "id": "\(groupID.uuidString)",
          "title": "Sunday Coast Run",
          "is_active": true,
          "created_at": "2026-07-14T08:15:30.123456+00:00",
          "meet_time": "2026-07-19T21:00:00+00:00",
          "meet_point": "Harbour car park",
          "hosted_by": "Samar",
          "member_count": 2,
          "is_owner": true,
          "is_member": true,
          "your_rsvp": "going",
          "members": [
            { "name": "Samar", "rsvp": "going", "is_you": true },
            { "name": "Alex", "rsvp": "maybe", "is_you": false }
          ],
          "route_id": "\(routeID.uuidString)",
          "route_title": "Coastal Loop",
          "distance_km": 84.6,
          "elevation_m": 720,
          "route": [[-36.8485, 174.7633], [-36.9000, 174.8200]]
        }
        """

        let payload = try JSONDecoder.supabase.decode(
            GroupRidePayload.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )
        let groupRide = payload.groupRide(shareToken: token)

        XCTAssertEqual(groupRide.id, groupID)
        XCTAssertEqual(groupRide.routeID, routeID)
        XCTAssertEqual(groupRide.yourRSVP, .going)
        XCTAssertEqual(groupRide.members.map(\.rsvp), [.going, .maybe])
        XCTAssertEqual(groupRide.route.count, 2)
        XCTAssertEqual(groupRide.route.first?.latitude, -36.8485)
        XCTAssertEqual(groupRide.plannedRoute.route, groupRide.route)
        XCTAssertEqual(groupRide.visibility, .inviteOnly)
        XCTAssertEqual(groupRide.status, .scheduled)
        XCTAssertEqual(groupRide.goingCount, 1)
        XCTAssertEqual(groupRide.maybeCount, 1)
        XCTAssertTrue(groupRide.inviteURL?.absoluteString.contains(token.uuidString) == true)
    }

    func testMyGroupRideSummaryDecodesMeetingAndOwnership() throws {
        let token = UUID()
        let json = """
        [{
          "title": "Sunday Coast Run",
          "share_token": "\(token.uuidString)",
          "meet_time": null,
          "meet_point": "Harbour car park",
          "created_at": "2026-07-14T08:15:30+00:00",
          "is_owner": false,
          "member_count": 5,
          "route_title": "Coastal Loop"
        }]
        """

        let summaries = try JSONDecoder.supabase.decode(
            [GroupRideSummary].self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(summaries.first?.id, token)
        XCTAssertEqual(summaries.first?.memberCount, 5)
        XCTAssertEqual(summaries.first?.meetPoint, "Harbour car park")
        XCTAssertFalse(try XCTUnwrap(summaries.first).isOwner)
    }

    func testProductionGroupRidePayloadMapsSocialContract() throws {
        let token = UUID()
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Sunset Community Loop",
          "details": "Fuelled by 5:45. Relaxed pace.",
          "visibility": "community",
          "capacity": 8,
          "status": "scheduled",
          "is_active": true,
          "created_at": "2026-07-16T02:00:00.123456+00:00",
          "meet_time": "2026-07-18T05:45:00+00:00",
          "meet_point": "Browns Bay beach car park",
          "hosted_by": "Samar",
          "member_count": 6,
          "going_count": 5,
          "maybe_count": 1,
          "declined_count": 2,
          "is_owner": true,
          "is_member": true,
          "your_rsvp": "going",
          "members": [],
          "route_id": "\(UUID().uuidString)",
          "route_title": "Coast at Dusk",
          "distance_km": 67.2,
          "elevation_m": 540,
          "route": [[-36.71, 174.74], [-36.62, 174.80]]
        }
        """

        let payload = try JSONDecoder.supabase.decode(
            GroupRidePayload.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )
        let ride = payload.groupRide(shareToken: token)

        XCTAssertEqual(ride.visibility, .community)
        XCTAssertEqual(ride.status, .scheduled)
        XCTAssertEqual(ride.capacity, 8)
        XCTAssertEqual(ride.spotsRemaining, 3)
        XCTAssertFalse(ride.isFull)
        XCTAssertEqual(ride.goingCount, 5)
        XCTAssertEqual(ride.declinedCount, 2)
        XCTAssertEqual(ride.details, "Fuelled by 5:45. Relaxed pace.")
    }

    func testCommunitySummaryCalculatesCapacity() throws {
        let token = UUID()
        let json = """
        [{
          "title": "Sunday Social",
          "details": null,
          "share_token": "\(token.uuidString)",
          "meet_time": "2026-07-19T21:00:00+00:00",
          "hosted_by": "Alex",
          "host_region": "Auckland",
          "capacity": 4,
          "going_count": 4,
          "maybe_count": 2,
          "route_title": "Northern Arc",
          "distance_km": 92.5,
          "elevation_m": 810
        }]
        """

        let rides = try JSONDecoder.supabase.decode(
            [CommunityGroupRideSummary].self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )
        let ride = try XCTUnwrap(rides.first)

        XCTAssertEqual(ride.id, token)
        XCTAssertEqual(ride.spotsRemaining, 0)
        XCTAssertTrue(ride.isFull)
        XCTAssertEqual(ride.hostRegion, "Auckland")
    }

    func testGroupRideInviteParsesUniversalAndCustomLinks() throws {
        let token = UUID()
        let universal = try XCTUnwrap(URL(
            string: "https://memory-lanes-ride-journal-app.vercel.app/group.html?ride=\(token.uuidString)"
        ))
        let custom = try XCTUnwrap(URL(string: "memorylanes://group/\(token.uuidString)"))

        XCTAssertEqual(GroupRideInvite.parse(universal)?.shareToken, token)
        XCTAssertEqual(GroupRideInvite.parse(custom)?.shareToken, token)
    }

    func testGroupRideInviteRejectsUntrustedOrMalformedLinks() throws {
        let token = UUID()
        let untrusted = try XCTUnwrap(URL(string: "https://example.com/group.html?ride=\(token.uuidString)"))
        let malformed = try XCTUnwrap(URL(string: "memorylanes://group/not-a-token"))

        XCTAssertNil(GroupRideInvite.parse(untrusted))
        XCTAssertNil(GroupRideInvite.parse(malformed))
    }
}
