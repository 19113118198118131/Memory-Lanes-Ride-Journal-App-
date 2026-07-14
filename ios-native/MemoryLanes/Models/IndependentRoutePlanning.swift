import Foundation

enum RouteMood: String, CaseIterable, Identifiable, Sendable {
    case flowing, twisty, scenic, relaxed

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .flowing: "waveform.path"
        case .twisty: "point.topleft.down.to.point.bottomright.curvepath"
        case .scenic: "mountain.2.fill"
        case .relaxed: "leaf.fill"
        }
    }

    var averageSpeedKmH: Double {
        switch self {
        case .flowing: 62
        case .twisty: 48
        case .scenic: 54
        case .relaxed: 44
        }
    }

    var bearingBias: Double {
        switch self {
        case .flowing: 18
        case .twisty: 47
        case .scenic: 82
        case .relaxed: 124
        }
    }
}

enum RouteTime: String, CaseIterable, Identifiable, Sendable {
    case fortyFive, ninety, threeHours, halfDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fortyFive: "45 min"
        case .ninety: "1.5 hr"
        case .threeHours: "3 hr"
        case .halfDay: "Half day"
        }
    }

    var hours: Double {
        switch self {
        case .fortyFive: 0.75
        case .ninety: 1.5
        case .threeHours: 3
        case .halfDay: 4.5
        }
    }
}

struct RouteRoadContext: Equatable, Sendable {
    var scenicLandRatio: Double?
    var urbanRatio: Double?
    var motorwayRatio: Double?
    var unsuitableSurfaceRatio: Double?
    var elevationGainMeters: Double?

    static let geometryOnly = RouteRoadContext()

    var completeness: Double {
        let values = [scenicLandRatio, urbanRatio, motorwayRatio, unsuitableSurfaceRatio, elevationGainMeters]
        return Double(values.compactMap { $0 }.count) / Double(values.count)
    }
}

struct RouteCharacterProfile: Equatable, Sendable {
    let flow: Double
    let technicality: Double
    let variety: Double
    let straightRoadRatio: Double
    let distanceKm: Double
    let turnsPerKm: Double
}

struct RouteCharacterAssessment: Equatable, Sendable {
    enum Confidence: String, Sendable {
        case geometry, enriched

        var title: String {
            switch self {
            case .geometry: "Geometry preview"
            case .enriched: "Road-data enriched"
            }
        }
    }

    let modelVersion: Int
    let score: Int
    let label: String
    let reasons: [String]
    let confidence: Confidence
    let profile: RouteCharacterProfile
}

struct RoadRoute: Equatable, Sendable {
    let coordinates: [Coordinate]
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
    let context: RouteRoadContext
}

struct RouteCandidate: Identifiable, Sendable {
    let id: UUID
    let title: String
    let distanceKm: Double
    let time: String
    let elevationM: Double?
    let summary: String
    let preview: [Coordinate]
    let waypoints: [Coordinate]
    let character: RouteCharacterAssessment
    var recommendation: RouteRecommendation?

    init(
        id: UUID = UUID(),
        title: String,
        distanceKm: Double,
        time: String,
        elevationM: Double?,
        summary: String,
        preview: [Coordinate],
        waypoints: [Coordinate],
        character: RouteCharacterAssessment,
        recommendation: RouteRecommendation? = nil
    ) {
        self.id = id
        self.title = title
        self.distanceKm = distanceKm
        self.time = time
        self.elevationM = elevationM
        self.summary = summary
        self.preview = preview
        self.waypoints = waypoints
        self.character = character
        self.recommendation = recommendation
    }

    var matchVector: RouteMatchVector {
        RouteMatchVector(
            distanceKm: distanceKm,
            elevationGainM: elevationM ?? 0,
            turnsPerKm: character.profile.turnsPerKm
        )
    }

    var rankingScore: Double {
        let personal = recommendation.map { Double($0.matchPercent) } ?? Double(character.score)
        return Double(character.score) * 0.65 + personal * 0.35
    }

    var distance: String { String(format: "%.1f", distanceKm) }
    var elevation: String { elevationM.map { String(format: "%.0f", $0) } ?? "--" }

    var draft: PlannedRouteDraft {
        PlannedRouteDraft(
            title: title,
            distanceKm: distanceKm,
            elevationM: elevationM,
            waypoints: waypoints,
            route: preview
        )
    }
}

enum IndependentRoutePlanningError: LocalizedError {
    case noRoutes

    var errorDescription: String? {
        "No practical road loop was found from this start. Try a shorter time or another starting location."
    }
}
