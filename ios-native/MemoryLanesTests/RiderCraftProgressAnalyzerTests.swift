import XCTest
@testable import MemoryLanes

final class RiderCraftProgressAnalyzerTests: XCTestCase {
    func testProgressUsesLatestRateAndChoosesWeakestRecentSkill() throws {
        let latest = ride(
            daysAgo: 0,
            events: [.flatExit, .flatExit],
            scores: [
                "cornerEntry": 76,
                "exitDrive": 42,
                "brakingSmoothness": 81,
                "throttleSmoothness": 78,
                "consistency": 70
            ]
        )
        let previous = ride(
            daysAgo: 2,
            events: [.flatExit, .brakedDeep, .earlyApex],
            scores: [
                "cornerEntry": 70,
                "exitDrive": 50,
                "brakingSmoothness": 75,
                "throttleSmoothness": 74,
                "consistency": 68
            ]
        )

        let progress = RiderCraftProgressAnalyzer().analyze(rides: [previous, latest])

        XCTAssertEqual(progress.eligibleRideCount, 2)
        XCTAssertEqual(progress.currentRate ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(progress.comparisonRate ?? -1, 0.3, accuracy: 0.001)
        XCTAssertEqual(progress.focus?.kind, .exitDrive)
        XCTAssertEqual(progress.trend.count, 2)
    }

    func testBadgesNeverRewardSpeedDistanceOrFrequency() {
        let latest = ride(
            daysAgo: 0,
            events: [],
            scores: [
                "cornerEntry": 90,
                "exitDrive": 70,
                "brakingSmoothness": 85,
                "throttleSmoothness": 84,
                "consistency": 76
            ],
            cornerCount: 20
        )

        let progress = RiderCraftProgressAnalyzer().analyze(rides: [latest])

        XCTAssertTrue(progress.badges.first(where: { $0.kind == .settledEntry })?.isEarned == true)
        XCTAssertTrue(progress.badges.first(where: { $0.kind == .smoothHands })?.isEarned == true)
        XCTAssertTrue(progress.badges.first(where: { $0.kind == .repeatable })?.isEarned == true)
        XCTAssertFalse(progress.badges.first(where: { $0.kind == .wetDiscipline })?.isEarned == true)
    }

    private func ride(
        daysAgo: Int,
        events: [RiderCraftEvent.Kind],
        scores: [String: Double],
        cornerCount: Int = 10
    ) -> Ride {
        let signals = (0..<cornerCount).map { index in
            RiderCraftCornerSignal(
                cornerIndex: index + 1,
                startIndex: index * 10,
                apexIndex: index * 10 + 4,
                endIndex: index * 10 + 8,
                drive: events.contains(.flatExit) && index < events.filter({ $0 == .flatExit }).count ? 0 : 0.4,
                apexPosition: events.contains(.earlyApex) && index == 2 ? 0.2 : 0.5,
                brakeDepth: events.contains(.brakedDeep) && index == 1 ? 0.8 : 0.2
            )
        }
        let analysis = RiderCraftAnalyzer(minimumCornerCount: 1).analyze(corners: signals, brakingZones: [])
        return Ride(
            title: "Craft ride",
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date(),
            distanceMeters: 20_000,
            durationSeconds: 1_800,
            elevationGainMeters: 200,
            coachScores: scores,
            riderCraftSummary: RiderCraftStorageSummary(analysis: analysis)
        )
    }
}
