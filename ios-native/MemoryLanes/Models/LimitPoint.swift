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

struct LimitPointCorner: Codable, Identifiable, Hashable, Sendable {
    enum Direction: String, Codable, Hashable, Sendable {
        case left = "Left"
        case right = "Right"
    }

    enum Severity: Int, CaseIterable, Codable, Comparable, Hashable, Sendable {
        case room
        case thin
        case beyondView
        case severe

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .room: "Study"
            case .thin: "Tighter estimate"
            case .beyondView: "Restricted estimate"
            case .severe: "Strong restriction estimate"
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

struct LimitPointCalibrationReview: Identifiable, Codable, Equatable, Sendable {
    enum Decision: String, Codable, CaseIterable, Hashable, Sendable {
        case match
        case mismatch
        case unsure

        var title: String {
            switch self {
            case .match: "Matched"
            case .mismatch: "Did not match"
            case .unsure: "Not sure"
            }
        }
    }

    let rideID: UUID
    let modelVersion: Int
    let cornerID: Int
    let replayIndex: Int
    let severity: LimitPointCorner.Severity
    let decision: Decision
    let reviewedAt: Date

    var id: String { "\(rideID.uuidString)-v\(modelVersion)-corner-\(cornerID)" }
}

struct LimitPointAnalysis: Codable, Sendable {
    enum GeometrySource: String, Codable, Sendable {
        case plannedRoute = "Planned route polyline"
        case recordedTrack = "Recorded GPS track"
    }

    enum ObstructionSource: String, Codable, Sendable {
        case fixedResearch = "Fixed research assumption"
    }

    enum Confidence: String, Codable, Sendable {
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
