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
}
