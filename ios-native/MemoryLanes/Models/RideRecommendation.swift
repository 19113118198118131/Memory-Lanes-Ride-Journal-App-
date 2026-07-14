import Foundation

struct RideFeedback: Codable, Equatable, Sendable {
    enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
        case flowing, twisty, scenic, relaxed, technical, mixed

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum RepeatChoice: String, Codable, CaseIterable, Identifiable, Sendable {
        case yes, maybe, no

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var mood: Mood?
    var enjoyment: Int?
    var wouldRepeat: RepeatChoice?
    var reasons: [String: Bool]
    var at: Date?

    static let empty = RideFeedback(mood: nil, enjoyment: nil, wouldRepeat: nil, reasons: [:], at: nil)
}

struct RideFeatureRecord: Codable, Equatable, Sendable {
    struct Route: Codable, Equatable, Sendable {
        let distanceKm: Double?
        let durationMin: Double?
        let elevationGainM: Double?
        let avgSpeedKmh: Double?
        let turnsPerKm: Double?
        let cornerCount: Int?
        let avgCornerRadiusM: Double?
    }

    struct Technique: Codable, Equatable, Sendable {
        let cornerEntry: Double?
        let exitDrive: Double?
        let brakingSmoothness: Double?
        let throttleSmoothness: Double?
        let consistency: Double?
    }

    let schemaVersion: Int
    let route: Route
    let technique: Technique
}

struct RatedRideFeatures: Sendable {
    let features: RideFeatureRecord
    let enjoyment: Double
}

struct RouteMatchVector: Equatable, Sendable {
    let distanceKm: Double
    let elevationGainM: Double
    let turnsPerKm: Double

    var values: [Double] { [distanceKm, elevationGainM, turnsPerKm] }
}

struct RouteRecommendation: Equatable, Sendable {
    enum Confidence: String, Sendable {
        case high, medium, low
    }

    let matchPercent: Int
    let predictedEnjoyment: Double
    let confidence: Confidence
    let reasons: [String]
}
