import Foundation
import Testing
@testable import MemoryLanes

struct IndependentRoutePlannerTests {
    @Test func plannerProducesRankedCandidatesWithoutAHostedRoutingDependency() async throws {
        let planner = IndependentRoutePlanner(roadProvider: StubRoadProvider())
        let candidates = try await planner.candidates(
            mood: .twisty,
            time: .ninety,
            start: Coordinate(latitude: -36.85, longitude: 174.76)
        )

        #expect(candidates.count == 3)
        #expect(candidates.allSatisfy { $0.preview.count > 2 })
        #expect(candidates.allSatisfy { $0.character.confidence == .geometry })
        #expect(candidates.map(\.character.score) == candidates.map(\.character.score).sorted(by: >))
    }
}

private struct StubRoadProvider: RoadRouteProviding {
    func route(through waypoints: [Coordinate]) async throws -> RoadRoute {
        let coordinates = zip(waypoints, waypoints.dropFirst()).flatMap { start, end in
            (0..<12).map { step in
                let progress = Double(step) / 12
                let bow = sin(progress * .pi) * 0.002
                return Coordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * progress + bow,
                    longitude: start.longitude + (end.longitude - start.longitude) * progress - bow
                )
            }
        } + Array(waypoints.suffix(1))
        let distance = coordinates.totalTestDistanceMeters
        return RoadRoute(
            coordinates: coordinates,
            distanceMeters: distance,
            expectedTravelTime: distance / 14,
            context: .geometryOnly
        )
    }
}

private extension Array where Element == Coordinate {
    var totalTestDistanceMeters: Double {
        zip(self, dropFirst()).reduce(0) { total, pair in
            let latitudeMeters = (pair.1.latitude - pair.0.latitude) * 111_000
            let longitudeMeters = (pair.1.longitude - pair.0.longitude) * 88_000
            return total + hypot(latitudeMeters, longitudeMeters)
        }
    }
}
