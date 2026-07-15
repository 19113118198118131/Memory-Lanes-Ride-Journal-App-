import XCTest
@testable import MemoryLanes

final class NotificationPreferencesTests: XCTestCase {
    func testPreferencesDecodeSupabaseContract() throws {
        let json = """
        {
          "event_updates": true,
          "rsvp_updates": false,
          "ride_reminders": true,
          "quiet_hours": true,
          "timezone": "Pacific/Auckland",
          "updated_at": "2026-07-16T04:00:00.123456+12:00"
        }
        """

        let preferences = try JSONDecoder.supabase.decode(
            NotificationPreferences.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertTrue(preferences.eventUpdates)
        XCTAssertFalse(preferences.rsvpUpdates)
        XCTAssertTrue(preferences.rideReminders)
        XCTAssertTrue(preferences.quietHours)
        XCTAssertEqual(preferences.timezone, "Pacific/Auckland")
        XCTAssertNotNil(preferences.updatedAt)
    }

    func testDefaultPreferencesKeepUsefulGroupUpdatesOn() {
        let preferences = NotificationPreferences()

        XCTAssertTrue(preferences.eventUpdates)
        XCTAssertTrue(preferences.rsvpUpdates)
        XCTAssertTrue(preferences.rideReminders)
        XCTAssertTrue(preferences.quietHours)
        XCTAssertFalse(preferences.timezone.isEmpty)
    }

    func testRemovingMembershipClearsReminderEligibilityWithoutMutatingOriginal() throws {
        let groupRide = try makeGroupRide()
        let removed = groupRide.withoutMembership

        XCTAssertTrue(groupRide.isMember)
        XCTAssertEqual(groupRide.yourRSVP, .going)
        XCTAssertFalse(removed.isMember)
        XCTAssertNil(removed.yourRSVP)
    }

    private func makeGroupRide() throws -> GroupRide {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Sunday Loop",
          "visibility": "invite_only",
          "status": "scheduled",
          "is_active": true,
          "created_at": "2026-07-16T04:00:00+12:00",
          "meet_time": "2026-07-20T09:00:00+12:00",
          "meet_point": "Harbour car park",
          "member_count": 1,
          "going_count": 1,
          "maybe_count": 0,
          "declined_count": 0,
          "is_owner": false,
          "is_member": true,
          "your_rsvp": "going",
          "members": [],
          "route_id": "\(UUID().uuidString)",
          "route_title": "Coast",
          "distance_km": 60,
          "route": [[-36.8, 174.7], [-36.9, 174.8]]
        }
        """
        let payload = try JSONDecoder.supabase.decode(
            GroupRidePayload.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )
        return payload.groupRide(shareToken: UUID())
    }
}
