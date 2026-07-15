import XCTest
@testable import MemoryLanes

final class AnalyticsDisplaySamplerTests: XCTestCase {
    func testShortSeriesIsUnchanged() {
        XCTAssertEqual(AnalyticsDisplaySampler.sample([1, 2, 3], limit: 10), [1, 2, 3])
    }

    func testLongSeriesKeepsEndpointsAndRequestedLimit() {
        let values = Array(0..<30_000)
        let sampled = AnalyticsDisplaySampler.sample(values, limit: 1_200)

        XCTAssertEqual(sampled.count, 1_200)
        XCTAssertEqual(sampled.first, values.first)
        XCTAssertEqual(sampled.last, values.last)
    }

    func testEmptyAndInvalidLimitsAreSafe() {
        XCTAssertTrue(AnalyticsDisplaySampler.sample([Int](), limit: 100).isEmpty)
        XCTAssertTrue(AnalyticsDisplaySampler.sample([1, 2, 3], limit: 0).isEmpty)
    }
}
