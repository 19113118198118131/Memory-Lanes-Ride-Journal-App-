import Foundation
import XCTest
@testable import MemoryLanes

final class AccountDataExportServiceTests: XCTestCase {
    func testJSONValueRoundTripPreservesUnknownFields() throws {
        let source = Data(#"[{"id":"ride-1","future_field":{"enabled":true,"score":92.5},"tags":["coast","wet"]}]"#.utf8)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: source)
        let encoded = try JSONEncoder().encode(decoded)
        let roundTrip = try JSONDecoder().decode(JSONValue.self, from: encoded)

        XCTAssertEqual(roundTrip, decoded)
    }

    func testGPXStoragePathsIgnoreMissingValuesAndRemoveDuplicates() throws {
        let source = Data(#"[{"gpx_path":"user/one.gpx"},{"gpx_path":null},{"title":"No GPX"},{"gpx_path":"user/one.gpx"},{"gpx_path":"user/two.gpx"}]"#.utf8)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: source)

        XCTAssertEqual(decoded.gpxStoragePaths, ["user/one.gpx", "user/two.gpx"])
    }

    func testExportPackageContainsAccountAndRawRecords() throws {
        let userID = UUID()
        let package = AccountDataExport(
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            account: AccountExportIdentity(userID: userID, email: "rider@example.com"),
            rideLogs: .array([.object(["title": .string("Coastal Ride")])]),
            plannedRoutes: .array([]),
            gpxFiles: [
                GPXFileExport(storagePath: "user/ride.gpx", xml: "<gpx />", base64: nil, error: nil)
            ]
        )
        let data = try JSONEncoder().encode(package)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let account = try XCTUnwrap(object["account"] as? [String: Any])
        let rides = try XCTUnwrap(object["rideLogs"] as? [[String: Any]])
        let files = try XCTUnwrap(object["gpxFiles"] as? [[String: Any]])

        XCTAssertEqual(object["formatVersion"] as? Int, 1)
        XCTAssertEqual(account["userID"] as? String, userID.uuidString)
        XCTAssertEqual(rides.first?["title"] as? String, "Coastal Ride")
        XCTAssertEqual(files.first?["xml"] as? String, "<gpx />")
    }
}
