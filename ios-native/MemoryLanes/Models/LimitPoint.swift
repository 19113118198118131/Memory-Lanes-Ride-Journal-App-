import Foundation

enum LimitPointFeature {
    #if DEBUG
    static let isResearchPreviewEnabled = true
    #else
    static let isResearchPreviewEnabled = false
    #endif
}

struct LimitPointSample: Sendable {
    let coordinate: Coordinate
    let speedKmh: Double?
    let replayIndex: Int
}

struct LimitPointCorner: Identifiable, Hashable, Sendable {
    enum Direction: String, Sendable {
        case left = "Left"
        case right = "Right"
    }

    enum Severity: Int, Comparable, Sendable {
        case room
        case thin
        case beyondView
        case severe

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .room: "No model deficit"
            case .thin: "Thin margin"
            case .beyondView: "Beyond view"
            case .severe: "Severe deficit"
            }
        }
    }

    let index: Int
    let startIndex: Int
    let apexIndex: Int
    let endIndex: Int
    let replayIndex: Int
    let coordinate: Coordinate
    let direction: Direction
    let radiusMeters: Double
    let sweepDegrees: Double
    let referenceSpeedKmh: Double
    let sightDistanceMeters: Double
    let stoppingDistanceMeters: Double
    let marginMeters: Double
    let severity: Severity

    var id: Int { apexIndex }
}

struct LimitPointAnalysis: Sendable {
    enum GeometrySource: String, Sendable {
        case plannedRoute = "Planned route polyline"
        case recordedTrack = "Recorded GPS track"
    }

    enum ObstructionSource: String, Sendable {
        case fixedResearch = "Fixed research assumption"
    }

    enum Confidence: String, Sendable {
        case low = "Low confidence"
    }

    let modelVersion: Int
    let route: [Coordinate]
    let corners: [LimitPointCorner]
    let obstructionOffsetMeters: Double
    let reactionSeconds: Double
    let decelerationMetersPerSecondSquared: Double
    let usesRecordedSpeed: Bool
    let wetModel: Bool
    let geometrySource: GeometrySource
    let obstructionSource: ObstructionSource
    let confidence: Confidence

    var beyondViewCount: Int { corners.filter { $0.marginMeters < 0 }.count }
    var severeCount: Int { corners.filter { $0.marginMeters < -20 }.count }
    var worstCorner: LimitPointCorner? { corners.min { $0.marginMeters < $1.marginMeters } }
}
