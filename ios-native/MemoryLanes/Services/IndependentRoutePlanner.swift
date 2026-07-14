import Foundation

struct IndependentRoutePlanner: Sendable {
    private let roadProvider: any RoadRouteProviding
    private let characterAnalyzer: RouteCharacterAnalyzer

    init(
        roadProvider: any RoadRouteProviding = MapKitRoadRouteProvider(),
        characterAnalyzer: RouteCharacterAnalyzer = RouteCharacterAnalyzer()
    ) {
        self.roadProvider = roadProvider
        self.characterAnalyzer = characterAnalyzer
    }

    func candidates(mood: RouteMood, time: RouteTime, start: Coordinate) async throws -> [RouteCandidate] {
        let targetDistance = mood.averageSpeedKmH * time.hours
        let attempts = candidateAttempts(mood: mood)
        var candidates: [RouteCandidate] = []

        for attempt in attempts {
            try Task.checkCancellation()
            let anchors = routeAnchors(
                start: start,
                distanceKm: targetDistance * attempt.distanceScale,
                bearingOffset: attempt.bearingOffset
            )
            guard let roadRoute = try? await roadProvider.route(through: anchors) else { continue }
            let preview = roadRoute.coordinates.decimated(maxCount: 1_600)
            let character = characterAnalyzer.assess(
                coordinates: preview,
                context: roadRoute.context,
                mood: mood
            )
            candidates.append(
                RouteCandidate(
                    title: attempt.title,
                    distanceKm: roadRoute.distanceMeters / 1_000,
                    time: formattedDuration(roadRoute.expectedTravelTime),
                    elevationM: roadRoute.context.elevationGainMeters,
                    summary: attempt.summary,
                    preview: preview,
                    waypoints: anchors,
                    character: character
                )
            )
        }

        guard !candidates.isEmpty else { throw IndependentRoutePlanningError.noRoutes }
        return Array(candidates.sorted { $0.character.score > $1.character.score }.prefix(3))
    }

    private func candidateAttempts(mood: RouteMood) -> [CandidateAttempt] {
        [
            CandidateAttempt(
                title: "\(mood.title) Loop",
                distanceScale: 1,
                bearingOffset: mood.bearingBias,
                summary: "Balanced road loop · returns to your start"
            ),
            CandidateAttempt(
                title: "\(mood.title) Alternate",
                distanceScale: 0.86,
                bearingOffset: mood.bearingBias + 96,
                summary: "Shorter option · different roads home"
            ),
            CandidateAttempt(
                title: "\(mood.title) North Loop",
                distanceScale: 0.92,
                bearingOffset: mood.bearingBias + 188,
                summary: "Alternate road character · returns to your start"
            ),
            CandidateAttempt(
                title: "\(mood.title) South Loop",
                distanceScale: 0.78,
                bearingOffset: mood.bearingBias + 274,
                summary: "Compact road loop · returns to your start"
            )
        ]
    }

    private func routeAnchors(start: Coordinate, distanceKm: Double, bearingOffset: Double) -> [Coordinate] {
        let leg = max(distanceKm / 5.2, 1.8)
        let first = start.projected(distanceKm: leg, bearingDegrees: bearingOffset)
        let second = first.projected(distanceKm: leg * 0.82, bearingDegrees: bearingOffset + 68)
        let third = second.projected(distanceKm: leg * 1.05, bearingDegrees: bearingOffset + 152)
        let fourth = third.projected(distanceKm: leg * 0.76, bearingDegrees: bearingOffset + 232)
        return [start, first, second, third, fourth, start]
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded()), 1)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

private struct CandidateAttempt: Sendable {
    let title: String
    let distanceScale: Double
    let bearingOffset: Double
    let summary: String
}
