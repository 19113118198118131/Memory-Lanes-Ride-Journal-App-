import XCTest
@testable import MemoryLanes

final class RiderProfileTests: XCTestCase {
    func testProfileDecodesPrivateCommunityIdentity() throws {
        let userID = UUID()
        let json = """
        {
          "user_id": "\(userID.uuidString)",
          "display_name": "Samar",
          "region": "Auckland"
        }
        """

        let profile = try JSONDecoder.supabase.decode(
            RiderProfile.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(profile.userID, userID)
        XCTAssertEqual(profile.displayName, "Samar")
        XCTAssertEqual(profile.region, "Auckland")
    }

    func testProfileEncodesSupabaseColumnNames() throws {
        let userID = UUID()
        let profile = RiderProfile(userID: userID, displayName: "Alex", region: "Waikato")
        let data = try JSONEncoder.supabase.encode(profile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["user_id"].flatMap(UUID.init(uuidString:)), userID)
        XCTAssertEqual(object["display_name"], "Alex")
        XCTAssertEqual(object["region"], "Waikato")
    }
}
