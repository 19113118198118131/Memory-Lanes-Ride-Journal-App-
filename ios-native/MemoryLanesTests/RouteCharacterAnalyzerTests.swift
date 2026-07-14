import Foundation
import Testing
@testable import MemoryLanes

struct RouteCharacterAnalyzerTests {
    private let analyzer = RouteCharacterAnalyzer()

    @Test func straightRoadIsNotMistakenForTechnicalRoad() {
        let straight = (0..<80).map { index in
            Coordinate(latitude: -36.85 + Double(index) * 0.0004, longitude: 174.76)
        }
        let winding = (0..<80).map { index in
            let progress = Double(index)
            return Coordinate(
                latitude: -36.85 + progress * 0.00028,
                longitude: 174.76 + sin(progress * 0.42) * 0.0018
            )
        }

        let straightProfile = analyzer.profile(for: straight)
        let windingProfile = analyzer.profile(for: winding)

        #expect(straightProfile.straightRoadRatio > windingProfile.straightRoadRatio)
        #expect(windingProfile.technicality > straightProfile.technicality)
        #expect(windingProfile.turnsPerKm > straightProfile.turnsPerKm)
    }

    @Test func roadContextCanEnrichScenicScoreAndPenaliseMotorways() {
        let scenic = analyzer.assess(
            coordinates: windingLoop,
            context: RouteRoadContext(
                scenicLandRatio: 0.88,
                urbanRatio: 0.05,
                motorwayRatio: 0,
                unsuitableSurfaceRatio: 0,
                elevationGainMeters: 760
            ),
            mood: .scenic
        )
        let motorway = analyzer.assess(
            coordinates: windingLoop,
            context: RouteRoadContext(
                scenicLandRatio: 0.05,
                urbanRatio: 0.2,
                motorwayRatio: 0.8,
                unsuitableSurfaceRatio: 0,
                elevationGainMeters: 40
            ),
            mood: .scenic
        )

        #expect(scenic.score > motorway.score)
        #expect(scenic.confidence == .enriched)
        #expect(scenic.reasons.contains { $0.contains("natural") })
    }

    @Test func geometryOnlyAssessmentStatesItsConfidenceHonestly() {
        let result = analyzer.assess(coordinates: windingLoop, mood: .flowing)

        #expect(result.modelVersion == RouteCharacterAnalyzer.modelVersion)
        #expect(result.confidence == .geometry)
        #expect(result.score >= 0 && result.score <= 100)
        #expect(result.reasons.count == 2)
    }

    private var windingLoop: [Coordinate] {
        (0..<120).map { index in
            let angle = Double(index) / 119 * 2 * Double.pi
            let radius = 0.018 + sin(angle * 4) * 0.003
            return Coordinate(
                latitude: -36.85 + cos(angle) * radius,
                longitude: 174.76 + sin(angle) * radius
            )
        }
    }
}
