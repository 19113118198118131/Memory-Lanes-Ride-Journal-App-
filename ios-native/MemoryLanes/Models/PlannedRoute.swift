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

    func draftCopy(title copyTitle: String) -> PlannedRouteDraft {
        PlannedRouteDraft(
            title: copyTitle,
            distanceKm: distanceKm,
            elevationM: elevationM,
            waypoints: waypoints,
            route: route
        )
    }
}

struct PlannedRouteDraft: Hashable, Sendable {
    var title: String
    var distanceKm: Double?
    var elevationM: Double?
    var waypoints: [Coordinate]
    var route: [Coordinate]

    static func edited(title: String, waypoints: [Coordinate], baseElevationM: Double?) -> PlannedRouteDraft {
        let route = Self.routeLine(for: waypoints)
        return PlannedRouteDraft(
            title: title,
            distanceKm: route.totalDistanceKm,
            elevationM: baseElevationM,
            waypoints: waypoints,
            route: route
        )
    }

    static func routeLine(for waypoints: [Coordinate]) -> [Coordinate] {
        guard waypoints.count > 1 else { return waypoints }
        var route: [Coordinate] = []
        for index in waypoints.indices.dropLast() {
            let from = waypoints[index]
            let to = waypoints[index + 1]
            let steps = 18
            for step in 0..<steps {
                let progress = Double(step) / Double(steps)
                route.append(from.interpolated(to: to, progress: progress))
            }
        }
        if let last = waypoints.last {
            route.append(last)
        }
        return route
    }
}

private extension Coordinate {
    func interpolated(to other: Coordinate, progress: Double) -> Coordinate {
        Coordinate(
            latitude: latitude + (other.latitude - latitude) * progress,
            longitude: longitude + (other.longitude - longitude) * progress
        )
    }

    func distanceKm(to other: Coordinate) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let startLat = latitude * .pi / 180
        let endLat = other.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            sin(dLon / 2) * sin(dLon / 2) * cos(startLat) * cos(endLat)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }
}

private extension Array where Element == Coordinate {
    var totalDistanceKm: Double {
        guard count > 1 else { return 0 }
        return zip(self, dropFirst()).reduce(0) { total, pair in
            total + pair.0.distanceKm(to: pair.1)
        }
    }
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
