import Testing
@testable import MemoryLanes

struct RideRecommendationEngineTests {
    @Test func waitsForFourCompleteRatedRides() {
        let engine = RideRecommendationEngine(ratedRides: Array(sampleRides.prefix(3)))

        #expect(engine.isReady == false)
        #expect(engine.ratedCount == 3)
        #expect(engine.score(candidate(distance: 80, elevation: 700, turns: 4.8)) == nil)
    }

    @Test func favoursCandidateCloseToHighlyRatedRides() throws {
        let engine = RideRecommendationEngine(ratedRides: sampleRides)
        let favourite = try #require(engine.score(candidate(distance: 82, elevation: 720, turns: 5.1)))
        let motorway = try #require(engine.score(candidate(distance: 190, elevation: 80, turns: 0.4)))

        #expect(engine.isReady)
        #expect(favourite.matchPercent > motorway.matchPercent)
        #expect(favourite.reasons.contains { $0.contains("Similar") })
    }

    @Test func confidenceReflectsNearestKnownRide() throws {
        let engine = RideRecommendationEngine(ratedRides: sampleRides)
        let exact = try #require(engine.score(candidate(distance: 80, elevation: 700, turns: 5)))

        #expect(exact.confidence == .high)
        #expect(exact.predictedEnjoyment >= 4)
    }

    private var sampleRides: [RatedRideFeatures] {
        [
            rated(distance: 80, elevation: 700, turns: 5, enjoyment: 5),
            rated(distance: 90, elevation: 820, turns: 5.5, enjoyment: 5),
            rated(distance: 65, elevation: 560, turns: 4.6, enjoyment: 4),
            rated(distance: 170, elevation: 120, turns: 0.7, enjoyment: 1),
            rated(distance: 145, elevation: 220, turns: 1.1, enjoyment: 2)
        ]
    }

    private func rated(distance: Double, elevation: Double, turns: Double, enjoyment: Double) -> RatedRideFeatures {
        RatedRideFeatures(
            features: RideFeatureRecord(
                schemaVersion: 1,
                route: .init(
                    distanceKm: distance,
                    durationMin: 90,
                    elevationGainM: elevation,
                    avgSpeedKmh: 55,
                    turnsPerKm: turns,
                    cornerCount: nil,
                    avgCornerRadiusM: nil
                ),
                technique: .init(
                    cornerEntry: nil,
                    exitDrive: nil,
                    brakingSmoothness: nil,
                    throttleSmoothness: nil,
                    consistency: nil
                )
            ),
            enjoyment: enjoyment
        )
    }

    private func candidate(distance: Double, elevation: Double, turns: Double) -> RouteMatchVector {
        RouteMatchVector(distanceKm: distance, elevationGainM: elevation, turnsPerKm: turns)
    }
}
