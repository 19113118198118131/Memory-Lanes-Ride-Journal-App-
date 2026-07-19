import Foundation

enum NavigationManeuver: String, Codable, Equatable, Sendable {
    case start
    case straight
    case slightLeft
    case left
    case sharpLeft
    case slightRight
    case right
    case sharpRight
    case keepLeft
    case keepRight
    case merge
    case exitLeft
    case exitRight
    case roundabout
    case uTurnLeft
    case uTurnRight
    case arrive

    var symbol: String {
        switch self {
        case .start, .straight: "arrow.up"
        case .slightLeft, .keepLeft: "arrow.up.left"
        case .left, .sharpLeft: "arrow.turn.up.left"
        case .slightRight, .keepRight: "arrow.up.right"
        case .right, .sharpRight: "arrow.turn.up.right"
        case .merge: "arrow.merge"
        case .exitLeft: "arrow.up.left"
        case .exitRight: "arrow.up.right"
        case .roundabout: "arrow.clockwise.circle.fill"
        case .uTurnLeft: "arrow.uturn.left"
        case .uTurnRight: "arrow.uturn.right"
        case .arrive: "flag.checkered"
        }
    }
}

struct NavigationInstruction: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let notice: String?
    let maneuver: NavigationManeuver
    let startsAtMeters: Double

    var spokenText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TurnByTurnRoute: Equatable, Sendable {
    let coordinates: [Coordinate]
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
    let instructions: [NavigationInstruction]
}

enum NavigationRouteState: String, Equatable, Sendable {
    case locating
    case onRoute
    case nearRoute
    case offRoute
    case arrived

    var title: String {
        switch self {
        case .locating: "Finding route"
        case .onRoute: "On route"
        case .nearRoute: "Near route"
        case .offRoute: "Off route"
        case .arrived: "Arrived"
        }
    }
}

struct TurnByTurnSnapshot: Equatable, Sendable {
    let state: NavigationRouteState
    let instruction: NavigationInstruction?
    let upcomingInstruction: NavigationInstruction?
    let distanceToManeuverMeters: Double?
    let remainingDistanceMeters: Double
    let remainingTravelTime: TimeInterval
    let progressPercent: Double
    let deviationMeters: Double?
    let matchedDistanceMeters: Double

    var guidanceTitle: String {
        switch state {
        case .locating:
            "Finding route"
        case .offRoute:
            "Finding a safe return"
        case .arrived:
            "You have arrived"
        case .onRoute, .nearRoute:
            instruction?.text ?? "Continue on route"
        }
    }

    var guidanceSymbol: String {
        switch state {
        case .locating: "location.magnifyingglass"
        case .offRoute: "location.fill.viewfinder"
        case .arrived: NavigationManeuver.arrive.symbol
        case .onRoute, .nearRoute: instruction?.maneuver.symbol ?? NavigationManeuver.straight.symbol
        }
    }

    var maneuverDistanceText: String {
        guard let distanceToManeuverMeters else { return "" }
        if distanceToManeuverMeters >= 1_000 {
            return String(format: "%.1f km", distanceToManeuverMeters / 1_000)
        }
        let rounded = max(10, (distanceToManeuverMeters / 10).rounded() * 10)
        return String(format: "%.0f m", rounded)
    }

    var remainingDistanceText: String {
        if remainingDistanceMeters >= 1_000 {
            return String(format: "%.1f km", remainingDistanceMeters / 1_000)
        }
        return String(format: "%.0f m", max(remainingDistanceMeters, 0))
    }

    var etaText: String {
        let minutes = max(Int((remainingTravelTime / 60).rounded()), 0)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

enum TurnByTurnNavigationError: LocalizedError, Equatable {
    case noRoute
    case invalidRoute

    var errorDescription: String? {
        switch self {
        case .noRoute:
            "Turn-by-turn directions are unavailable for this route. Route recording will continue."
        case .invalidRoute:
            "This saved route does not contain enough road geometry for navigation."
        }
    }
}
