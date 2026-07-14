import Foundation

@MainActor
protocol RouteServing {
    func fetchRoutes() async throws -> [PlannedRoute]
    func createRoute(_ draft: PlannedRouteDraft) async throws -> PlannedRoute
    func updateRouteTitle(_ title: String, for route: PlannedRoute) async throws -> PlannedRoute
    func setSharing(_ isPublic: Bool, for route: PlannedRoute) async throws -> PlannedRoute
    func deleteRoute(_ route: PlannedRoute) async throws
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

    func createRoute(_ draft: PlannedRouteDraft) async throws -> PlannedRoute {
        try await Task.sleep(for: .milliseconds(250))
        if let failure { throw failure }
        return PlannedRoute(
            id: UUID(),
            title: draft.title,
            distanceKm: draft.distanceKm,
            elevationM: draft.elevationM,
            waypoints: draft.waypoints,
            route: draft.route,
            createdAt: Date(),
            isPublic: false,
            shareToken: nil
        )
    }

    func updateRouteTitle(_ title: String, for route: PlannedRoute) async throws -> PlannedRoute {
        try await Task.sleep(for: .milliseconds(250))
        if let failure { throw failure }
        var updated = route
        updated.title = title
        return updated
    }

    func setSharing(_ isPublic: Bool, for route: PlannedRoute) async throws -> PlannedRoute {
        try await Task.sleep(for: .milliseconds(250))
        if let failure { throw failure }
        var updated = route
        updated.isPublic = isPublic
        updated.shareToken = isPublic ? (updated.shareToken ?? UUID()) : updated.shareToken
        return updated
    }

    func deleteRoute(_ route: PlannedRoute) async throws {
        try await Task.sleep(for: .milliseconds(250))
        if let failure { throw failure }
    }
}

struct RouteService: RouteServing {
    var client = SupabaseHTTPClient()
    var accessToken: () -> String?
    var userID: () -> UUID?

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

    func createRoute(_ draft: PlannedRouteDraft) async throws -> PlannedRoute {
        guard let token = accessToken(), let userID = userID() else { throw RideServiceError.notAuthenticated }
        let payload = PlannedRouteInsertPayload(userID: userID, draft: draft)
        let rows: [SupabasePlannedRouteRow] = try await client.post(
            path: "rest/v1/planned_routes",
            queryItems: [URLQueryItem(name: "select", value: "id,title,distance_km,elevation_m,waypoints,route,created_at,is_public,share_token")],
            body: payload,
            accessToken: token,
            prefer: "return=representation"
        )
        guard let route = rows.first?.plannedRoute else { throw RouteServiceError.missingInsertedRoute }
        return route
    }

    func updateRouteTitle(_ title: String, for route: PlannedRoute) async throws -> PlannedRoute {
        guard let token = accessToken() else { throw RideServiceError.notAuthenticated }
        let payload = RouteTitleUpdatePayload(title: title)
        let rows: [SupabasePlannedRouteRow] = try await client.patch(
            path: "rest/v1/planned_routes",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(route.id.uuidString)"),
                URLQueryItem(name: "select", value: "id,title,distance_km,elevation_m,waypoints,route,created_at,is_public,share_token")
            ],
            body: payload,
            accessToken: token,
            prefer: "return=representation"
        )
        return rows.first?.plannedRoute ?? route
    }

    func setSharing(_ isPublic: Bool, for route: PlannedRoute) async throws -> PlannedRoute {
        guard let token = accessToken() else { throw RideServiceError.notAuthenticated }
        let payload = RouteShareUpdatePayload(isPublic: isPublic)
        let rows: [SupabasePlannedRouteRow] = try await client.patch(
            path: "rest/v1/planned_routes",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(route.id.uuidString)"),
                URLQueryItem(name: "select", value: "id,title,distance_km,elevation_m,waypoints,route,created_at,is_public,share_token")
            ],
            body: payload,
            accessToken: token,
            prefer: "return=representation"
        )
        return rows.first?.plannedRoute ?? route
    }

    func deleteRoute(_ route: PlannedRoute) async throws {
        guard let token = accessToken() else { throw RideServiceError.notAuthenticated }
        try await client.delete(
            path: "rest/v1/planned_routes",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(route.id.uuidString)")],
            accessToken: token
        )
    }
}

enum RouteServiceError: LocalizedError {
    case notImplemented
    case missingInsertedRoute

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Route syncing is not connected yet."
        case .missingInsertedRoute:
            return "The route was saved, but Supabase did not return it."
        }
    }
}

private struct PlannedRouteInsertPayload: Encodable {
    let userID: UUID
    let title: String
    let distanceKm: Double?
    let elevationM: Double?
    let waypoints: [WaypointInsertPayload]
    let route: [RouteCoordinateInsertPayload]

    init(userID: UUID, draft: PlannedRouteDraft) {
        self.userID = userID
        title = draft.title
        distanceKm = draft.distanceKm
        elevationM = draft.elevationM
        waypoints = draft.waypoints.map(WaypointInsertPayload.init(coordinate:))
        route = draft.route.map(RouteCoordinateInsertPayload.init(coordinate:))
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case title
        case distanceKm = "distance_km"
        case elevationM = "elevation_m"
        case waypoints
        case route
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

private struct RouteShareUpdatePayload: Encodable {
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case isPublic = "is_public"
    }
}

private struct RouteTitleUpdatePayload: Encodable {
    let title: String
}

private struct WaypointPayload: Decodable {
    let lat: Double
    let lng: Double

    var coordinate: Coordinate {
        Coordinate(latitude: lat, longitude: lng)
    }
}

private struct WaypointInsertPayload: Encodable {
    let lat: Double
    let lng: Double

    init(coordinate: Coordinate) {
        lat = coordinate.latitude
        lng = coordinate.longitude
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

private struct RouteCoordinateInsertPayload: Encodable {
    let coordinate: Coordinate

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(coordinate.latitude)
        try container.encode(coordinate.longitude)
    }
}
