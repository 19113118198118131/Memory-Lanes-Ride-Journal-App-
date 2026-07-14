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

    var inviteURL: URL? {
        guard let shareToken else { return nil }
        return URL(string: "https://memory-lanes-ride-journal-app.vercel.app/route.html?share=\(shareToken.uuidString)")
    }

    var gpxFileName: String {
        let clean = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(clean.isEmpty ? "planned-route" : clean).gpx"
    }

    var gpxText: String {
        let points = route.map { coordinate in
            "    <rtept lat=\"\(coordinate.latitude)\" lon=\"\(coordinate.longitude)\"></rtept>"
        }
        .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Memory Lanes" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(title.xmlEscaped)</name>
          </metadata>
          <rte>
            <name>\(title.xmlEscaped)</name>
        \(points)
          </rte>
        </gpx>
        """
    }
}

struct PlannedRouteDraft: Hashable, Sendable {
    var title: String
    var distanceKm: Double?
    var elevationM: Double?
    var waypoints: [Coordinate]
    var route: [Coordinate]
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
