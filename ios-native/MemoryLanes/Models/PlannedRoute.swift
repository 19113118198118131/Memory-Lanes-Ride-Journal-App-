import Foundation

struct PlannedRoute: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var distanceKm: Double?
    var elevationM: Double?
    var waypoints: [Coordinate]
    var route: [Coordinate]
    var createdAt: Date
    var isPublic: Bool
    var shareToken: UUID?

    var distanceText: String {
        guard let distanceKm else { return "--" }
        return String(format: "%.1f", distanceKm)
    }

    var elevationText: String {
        guard let elevationM else { return "--" }
        return String(format: "%.0f", elevationM)
    }

    var estimatedTimeText: String {
        guard let distanceKm else { return "--" }
        let hours = distanceKm / 58
        let minutes = Int((hours * 60).rounded())
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    var summary: String {
        let date = createdAt.formatted(.relative(presentation: .named))
        let waypointText = "\(waypoints.count) waypoint\(waypoints.count == 1 ? "" : "s")"
        return "\(waypointText) · \(isPublic ? "Shared" : "Private") · \(date)"
    }
}
