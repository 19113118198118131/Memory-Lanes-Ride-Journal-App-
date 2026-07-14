import Foundation

@MainActor
protocol RouteServing {
    func fetchRoutes() async throws -> [PlannedRoute]
}

struct PreviewRouteService: RouteServing {
    var routes: [PlannedRoute] = SampleData.plannedRoutes
    var failure: RouteServiceError? = nil
    var delay: Duration = .milliseconds(350)

    func fetchRoutes() async throws -> [PlannedRoute] {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        return routes
    }
}

struct RouteService: RouteServing {
    var client = SupabaseHTTPClient()
    var accessToken: () -> String?

    func fetchRoutes() async throws -> [PlannedRoute] {
        guard let token = accessToken() else { throw RideServiceError.notAuthenticated }
        let rows: [SupabasePlannedRouteRow] = try await client.get(
            path: "rest/v1/planned_routes",
            queryItems: [
                URLQueryItem(name: "select", value: "id,title,distance_km,elevation_m,waypoints,route,created_at,is_public,share_token"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            accessToken: token
        )
        return rows.map(\.plannedRoute)
    }
}

enum RouteServiceError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Route syncing is not connected yet."
        }
    }
}

private struct SupabasePlannedRouteRow: Decodable {
    let id: UUID
    let title: String?
    let distanceKm: Double?
    let elevationM: Double?
    let waypoints: [WaypointPayload]?
    let route: [RouteCoordinatePayload]?
    let createdAt: String?
    let isPublic: Bool?
    let shareToken: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case distanceKm = "distance_km"
        case elevationM = "elevation_m"
        case waypoints
        case route
        case createdAt = "created_at"
        case isPublic = "is_public"
        case shareToken = "share_token"
    }

    var plannedRoute: PlannedRoute {
        PlannedRoute(
            id: id,
            title: cleanTitle,
            distanceKm: distanceKm,
            elevationM: elevationM,
            waypoints: waypoints?.map(\.coordinate) ?? [],
            route: route?.map(\.coordinate) ?? [],
            createdAt: parsedCreatedAt,
            isPublic: isPublic ?? false,
            shareToken: shareToken
        )
    }

    private var parsedCreatedAt: Date {
        guard let createdAt else { return Date() }
        if let date = ISO8601DateFormatter().date(from: createdAt) { return date }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: createdAt) ?? Date()
    }

    private var cleanTitle: String {
        guard let title, !title.isEmpty else { return "Untitled Route" }
        return title
    }
}

private struct WaypointPayload: Decodable {
    let lat: Double
    let lng: Double

    var coordinate: Coordinate {
        Coordinate(latitude: lat, longitude: lng)
    }
}

private struct RouteCoordinatePayload: Decodable {
    let coordinate: Coordinate

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let latitude = try container.decode(Double.self)
        let longitude = try container.decode(Double.self)
        coordinate = Coordinate(latitude: latitude, longitude: longitude)
    }
}
