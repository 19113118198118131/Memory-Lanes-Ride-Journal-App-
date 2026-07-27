import CoreLocation
import XCTest
@testable import MemoryLanes

final class GPXParserTests: XCTestCase {
    func testParsesTimedTrackAndDerivesSpeed() throws {
        let data = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
              <trk><trkseg>
                <trkpt lat="-36.8485" lon="174.7633"><ele>12</ele><time>2026-01-01T00:00:00Z</time></trkpt>
                <trkpt lat="-36.8485" lon="174.7643"><ele>17</ele><time>2026-01-01T00:00:10Z</time></trkpt>
              </trkseg></trk>
            </gpx>
            """.utf8
        )

        let track = try GPXParser().parse(data: data)

        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.durationSeconds, 10, accuracy: 0.001)
        XCTAssertGreaterThan(track.distanceMeters, 80)
        XCTAssertGreaterThan(track.replayPoints[1].speedKmh, 25)
        XCTAssertEqual(track.elevationGainMeters, 5, accuracy: 0.001)
    }

    func testMissingTimesReceiveStableFallbackTimeline() throws {
        let data = Data(
            """
            <gpx version="1.1">
              <trk><trkseg>
                <trkpt lat="-36.8485" lon="174.7633" />
                <trkpt lat="-36.8485" lon="174.7634" />
                <trkpt lat="-36.8485" lon="174.7635" />
              </trkseg></trk>
            </gpx>
            """.utf8
        )

        let track = try GPXParser().parse(data: data)

        XCTAssertEqual(track.durationSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(track.replayPoints.map(\.elapsedSeconds), [0, 1, 2])
        XCTAssertGreaterThan(track.replayPoints[1].speedKmh, 0)
    }

    func testRejectsTrackWithoutEnoughPoints() {
        let data = Data("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\" /></trkseg></trk></gpx>".utf8)
        XCTAssertThrowsError(try GPXParser().parse(data: data)) { error in
            guard case GPXParserError.noTrackPoints = error else {
                return XCTFail("Expected noTrackPoints, got \(error)")
            }
        }
    }

    func testPrefersRecordedTrackWhenFileAlsoContainsPlannedRoute() throws {
        let data = Data(
            """
            <gpx>
              <rte>
                <rtept lat="-36.0" lon="174.0" />
                <rtept lat="-37.0" lon="175.0" />
              </rte>
              <trk><trkseg>
                <trkpt lat="-36.8485" lon="174.7633"><time>2026-01-01T00:00:00Z</time></trkpt>
                <trkpt lat="-36.8485" lon="174.7643"><time>2026-01-01T00:00:10Z</time></trkpt>
              </trkseg></trk>
            </gpx>
            """.utf8
        )

        let track = try GPXParser().parse(data: data)

        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.points.first?.longitude, 174.7633)
        XCTAssertEqual(track.durationSeconds, 10, accuracy: 0.001)
        XCTAssertLessThan(track.distanceMeters, 200)
    }

    func testImportLoaderReadsAValidFileAndSuggestsATitle() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sunday_Morning_Ride-\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(
            """
            <gpx version="1.1"><trk><trkseg>
              <trkpt lat="-36.8485" lon="174.7633" />
              <trkpt lat="-36.8485" lon="174.7643" />
            </trkseg></trk></gpx>
            """.utf8
        ).write(to: url, options: .atomic)

        let imported = try ImportedGPX.load(from: url)

        XCTAssertEqual(imported.fileName, url.lastPathComponent)
        XCTAssertTrue(imported.suggestedTitle.hasPrefix("Sunday Morning Ride-"))
        XCTAssertEqual(imported.track.points.count, 2)
    }

    func testImportLoaderRejectsOversizedFilesBeforeParsing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oversized-\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: ImportedGPX.maximumByteCount + 1)
            .write(to: url, options: .atomic)

        XCTAssertThrowsError(try ImportedGPX.load(from: url)) { error in
            guard case GPXImportViewError.fileTooLarge = error else {
                return XCTFail("Expected fileTooLarge, got \(error)")
            }
        }
    }
}
