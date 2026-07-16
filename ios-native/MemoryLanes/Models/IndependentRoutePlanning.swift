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

enum CompassDirection: String, CaseIterable, Identifiable, Sendable {
    case north, northEast, east, southEast, south, southWest, west, northWest

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .north: "N"
        case .northEast: "NE"
        case .east: "E"
        case .southEast: "SE"
        case .south: "S"
        case .southWest: "SW"
        case .west: "W"
        case .northWest: "NW"
        }
    }

    var title: String {
        switch self {
        case .north: "North"
        case .northEast: "North east"
        case .east: "East"
        case .southEast: "South east"
        case .south: "South"
        case .southWest: "South west"
        case .west: "West"
        case .northWest: "North west"
        }
    }

    var bearingDegrees: Double {
        switch self {
        case .north: 0
        case .northEast: 45
        case .east: 90
        case .southEast: 135
        case .south: 180
        case .southWest: 225
        case .west: 270
        case .northWest: 315
        }
    }

    var symbol: String {
        switch self {
        case .north: "arrow.up"
        case .northEast: "arrow.up.right"
        case .east: "arrow.right"
        case .southEast: "arrow.down.right"
        case .south: "arrow.down"
        case .southWest: "arrow.down.left"
        case .west: "arrow.left"
        case .northWest: "arrow.up.left"
        }
    }
}

struct RoutePlanRequest: Sendable {
    let primaryMood: RouteMood
    let secondaryMood: RouteMood?
    let time: RouteTime
    let start: Coordinate
    let targetDistanceKm: Double?
    let directions: Set<CompassDirection>

    init(
        mood: RouteMood,
        secondaryMood: RouteMood? = nil,
        time: RouteTime,
        start: Coordinate,
        targetDistanceKm: Double? = nil,
        direction: CompassDirection? = nil
    ) {
        self.primaryMood = mood
        self.secondaryMood = secondaryMood == mood ? nil : secondaryMood
        self.time = time
        self.start = start
        self.targetDistanceKm = targetDistanceKm
        self.directions = direction.map { [$0] } ?? []
    }

    init(
        primaryMood: RouteMood,
        secondaryMood: RouteMood? = nil,
        time: RouteTime,
        start: Coordinate,
        targetDistanceKm: Double? = nil,
        directions: Set<CompassDirection> = []
    ) {
        self.primaryMood = primaryMood
        self.secondaryMood = secondaryMood == primaryMood ? nil : secondaryMood
        self.time = time
        self.start = start
        self.targetDistanceKm = targetDistanceKm
        self.directions = directions
    }

    var mood: RouteMood { primaryMood }

    var effectiveTargetDistanceKm: Double {
        let blendedSpeed = secondaryMood.map {
            primaryMood.averageSpeedKmH * 0.7 + $0.averageSpeedKmH * 0.3
        } ?? primaryMood.averageSpeedKmH
        return targetDistanceKm ?? blendedSpeed * time.hours
    }

    var targetDuration: TimeInterval {
        time.hours * 60 * 60
    }
}

enum RouteMatchTier: Int, CaseIterable, Comparable, Sendable {
    case best
    case close
    case explore

    static func < (lhs: RouteMatchTier, rhs: RouteMatchTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .best: "Best Matches"
        case .close: "Close Matches"
        case .explore: "Explore Alternatives"
        }
    }

    var explanation: String {
        switch self {
        case .best: "Closest to the ride you asked for"
        case .close: "Good roads with a small time or distance trade-off"
        case .explore: "More variety when you feel flexible"
        }
    }
}

enum RoutePlanningLimits {
    static let distanceRange: ClosedRange<Double> = 15...300
    static let distanceStep: Double = 5
}

struct RoutePlanOptions: Equatable, Sendable {
    var primaryMood: RouteMood = .flowing
    var secondaryMood: RouteMood?
    var time: RouteTime = .ninety
    var targetDistanceKm: Double?
    var directions: Set<CompassDirection> = []

    var isDefault: Bool { self == Self() }

    var suggestedDistanceKm: Double {
        let averageSpeed = secondaryMood.map {
            primaryMood.averageSpeedKmH * 0.7 + $0.averageSpeedKmH * 0.3
        } ?? primaryMood.averageSpeedKmH
        return averageSpeed * time.hours
    }

    mutating func reset() {
        self = Self()
    }

    func request(start: Coordinate) -> RoutePlanRequest {
        RoutePlanRequest(
            primaryMood: primaryMood,
            secondaryMood: secondaryMood,
            time: time,
            start: start,
            targetDistanceKm: targetDistanceKm,
            directions: directions
        )
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
    let durationSeconds: TimeInterval
    let time: String
    // Settable so the view model can fill in Open-Meteo elevation after the
    // MapKit-only planner (which has no elevation data) returns candidates.
    var elevationM: Double?
    let summary: String
    let preview: [Coordinate]
    let waypoints: [Coordinate]
    let character: RouteCharacterAssessment
    let matchTier: RouteMatchTier
    let targetDeviation: Double
    let targetDeltaText: String
    var recommendation: RouteRecommendation?

    init(
        id: UUID = UUID(),
        title: String,
        distanceKm: Double,
        durationSeconds: TimeInterval,
        time: String,
        elevationM: Double?,
        summary: String,
        preview: [Coordinate],
        waypoints: [Coordinate],
        character: RouteCharacterAssessment,
        matchTier: RouteMatchTier = .best,
        targetDeviation: Double = 0,
        targetDeltaText: String = "On target",
        recommendation: RouteRecommendation? = nil
    ) {
        self.id = id
        self.title = title
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.time = time
        self.elevationM = elevationM
        self.summary = summary
        self.preview = preview
        self.waypoints = waypoints
        self.character = character
        self.matchTier = matchTier
        self.targetDeviation = targetDeviation
        self.targetDeltaText = targetDeltaText
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
    case requestLimitReached

    var errorDescription: String? {
        switch self {
        case .noRoutes:
            "Apple Maps could not build a usable road loop after several attempts. Check your connection, then regenerate or choose another start."
        case .requestLimitReached:
            "Apple Maps needs a brief pause before planning again. Wait about a minute, then try once more."
        }
    }
}
