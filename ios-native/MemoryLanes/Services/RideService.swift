import Foundation

// MARK: - RideServing
//
// The services layer is protocol-first so screens depend on an abstraction,
// not a concrete backend. `RideService` will wrap Supabase; `PreviewRideService`
// feeds sample data to previews and tests. Both are injected, never global.

// The protocol is `Sendable` and NOT `@MainActor`: its methods do network I/O,
// GPX parsing, and ride-coach analysis, all of which must run *off* the main
// actor. Conforming types are value types with Sendable state, so a `@MainActor`
// ViewModel can hold one and `await` it, hopping the heavy work off-main.
protocol RideServing: Sendable {
    func fetchRides() async throws -> [Ride]
    /// A decimated route polyline for a single ride's list thumbnail, loaded
    /// lazily per row so the list never blocks on downloading every ride's GPX.
    func routePreview(for ride: Ride) async throws -> [Coordinate]
    /// Full analysis for one ride, loaded when the rider opens it.
    func fetchDetail(for ride: Ride) async throws -> RideDetail
    func gpxData(for ride: Ride) async throws -> Data
    func saveMoments(_ moments: [Moment], for ride: Ride) async throws -> [Moment]
    func saveFeedback(_ feedback: RideFeedback, for ride: Ride) async throws -> RideFeedback
    func fetchRatedRideFeatures() async throws -> [RatedRideFeatures]
    func setSharing(_ isPublic: Bool, for ride: Ride) async throws -> Ride
}

// MARK: - Preview / demo implementation

/// Returns bundled sample rides after a short delay so skeleton loaders are
/// actually visible in previews and the simulator. Stores only `Sendable`
/// values (no `any Error` existential) so it passes complete concurrency checks.
struct PreviewRideService: RideServing {
    var delay: Duration = .milliseconds(600)
    var rides: [Ride] = SampleData.rides
    var failure: RideServiceError? = nil

    func fetchRides() async throws -> [Ride] {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        return rides
    }

    func routePreview(for ride: Ride) async throws -> [Coordinate] {
        try await Task.sleep(for: .milliseconds(200))
        if let failure { throw failure }
        return ride.routePreview.isEmpty ? SampleData.ridgeRoute : ride.routePreview
    }

    func fetchDetail(for ride: Ride) async throws -> RideDetail {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        // Sample detail is keyed to the hero ride; reuse its analysis with the
        // requested id so any previewed ride resolves to something to show.
        return RideDetail(
            id: ride.id,
            routePreview: SampleData.heroDetail.routePreview,
            replayPoints: SampleData.heroDetail.replayPoints,
            elevation: SampleData.heroDetail.elevation,
            corners: SampleData.heroDetail.corners,
            moments: SampleData.heroDetail.moments,
            weather: SampleData.heroDetail.weather,
            coachScore: SampleData.heroDetail.coachScore,
            coachScores: SampleData.heroDetail.coachScores,
            plannedRoute: SampleData.heroDetail.plannedRoute,
            routeMatch: SampleData.heroDetail.routeMatch,
            debrief: SampleData.heroDetail.debrief
        )
    }

    func gpxData(for ride: Ride) async throws -> Data {
        try await Task.sleep(for: .milliseconds(150))
        if let failure { throw failure }
        let points = (ride.routePreview.isEmpty ? SampleData.ridgeRoute : ride.routePreview)
            .map { coordinate in
                "    <trkpt lat=\"\(coordinate.latitude)\" lon=\"\(coordinate.longitude)\"></trkpt>"
            }
            .joined(separator: "\n")
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Memory Lanes" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(ride.title.xmlEscaped)</name>
            <trkseg>
        \(points)
            </trkseg>
          </trk>
        </gpx>
        """.utf8)
    }

    func saveMoments(_ moments: [Moment], for ride: Ride) async throws -> [Moment] {
        try await Task.sleep(for: .milliseconds(250))
        if let failure { throw failure }
        return moments
    }

    func saveFeedback(_ feedback: RideFeedback, for ride: Ride) async throws -> RideFeedback {
        try await Task.sleep(for: .milliseconds(180))
        if let failure { throw failure }
        return feedback
    }

    func fetchRatedRideFeatures() async throws -> [RatedRideFeatures] { [] }

    func setSharing(_ isPublic: Bool, for ride: Ride) async throws -> Ride {
        try await Task.sleep(for: .milliseconds(250))
        if let failure { throw failure }
        var updated = ride
        updated.isPublic = isPublic
        updated.shareToken = isPublic ? (updated.shareToken ?? UUID()) : updated.shareToken
        return updated
    }
}

// MARK: - Live implementation

struct RideService: RideServing {
    let accessToken: @Sendable () async -> String?
    private let client = SupabaseHTTPClient()
    private let weatherService = OpenMeteoWeatherService()

    init(accessToken: @escaping @Sendable () async -> String?) {
        self.accessToken = accessToken
    }

    func fetchRides() async throws -> [Ride] {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let rows: [SupabaseRideRow] = try await client.get(
            path: "rest/v1/ride_logs",
            queryItems: [
                URLQueryItem(name: "select", value: Self.rideSelectColumns),
                URLQueryItem(name: "order", value: "ride_date.desc")
            ],
            accessToken: token
        )
        // Return the list immediately. Route thumbnails are hydrated lazily,
        // per row (see `routePreview(for:)`), so opening the dashboard never
        // waits on downloading and parsing every ride's GPX file up front.
        return rows.map(\.ride)
    }

    func routePreview(for ride: Ride) async throws -> [Coordinate] {
        guard let gpxPath = ride.gpxPath else { return [] }
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let track = try await downloadTrack(path: gpxPath, accessToken: token)
        return track.routePreview
    }

    func fetchDetail(for ride: Ride) async throws -> RideDetail {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let metadata = try await fetchStoredMetadata(for: ride.id, accessToken: token)
        guard let gpxPath = ride.gpxPath else {
            return RideDetail(id: ride.id, routePreview: [], replayPoints: [], elevation: [], corners: [], moments: metadata.moments, weather: nil, coachScore: nil, coachScores: [], feedback: metadata.feedback, debrief: "This ride does not have an attached GPX file yet.")
        }
        let data = try await client.download(
            path: "storage/v1/object/gpx-files/\(gpxPath)",
            accessToken: token
        )
        let track = try GPXParser().parse(data: data)
        let history = (try? await fetchPastCoachHistory(excluding: ride.id, accessToken: token)) ?? .empty
        let coach = RideCoachAnalyzer().analyze(
            points: track.points,
            pastCorners: history.corners,
            recentScores: history.averageScores
        )
        let plannedRoute: PlannedRoute?
        if let plannedRouteID = ride.plannedRouteID {
            plannedRoute = try? await fetchPlannedRoute(id: plannedRouteID, accessToken: token)
        } else {
            plannedRoute = nil
        }
        let routeMatch = plannedRoute.flatMap {
            RouteMatchAnalyzer().analyze(plannedRoute: $0, actualTrack: track)
        }
        let weather: Weather?
        if let start = track.points.first {
            weather = try? await weatherService.fetchWeather(at: start.coordinate, rideDate: track.startedAt)
        } else {
            weather = nil
        }
        if let summary = coach.storageSummary {
            try? await saveCoachSummary(summary, for: ride.id, accessToken: token)
        }
        let features = RideFeatureExtractor().extract(
            ride: ride,
            points: track.points,
            scores: coach.scores,
            corners: coach.corners
        )
        try? await saveFeatureRecord(features, for: ride.id, accessToken: token)
        return RideDetail(
            id: ride.id,
            routePreview: track.routePreview,
            replayPoints: track.replayPoints,
            elevation: track.elevationSamples,
            corners: coach.corners,
            moments: metadata.moments,
            weather: weather,
            coachScore: coach.score,
            coachScores: coach.scores,
            analytics: coach.analytics,
            coachTrend: coach.trend,
            feedback: metadata.feedback,
            plannedRoute: plannedRoute,
            routeMatch: routeMatch,
            debrief: coach.debrief
        )
    }

    func gpxData(for ride: Ride) async throws -> Data {
        guard let gpxPath = ride.gpxPath else { throw RideServiceError.gpxUnavailable }
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        return try await client.download(
            path: "storage/v1/object/gpx-files/\(gpxPath)",
            accessToken: token
        )
    }

    func saveMoments(_ moments: [Moment], for ride: Ride) async throws -> [Moment] {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let payload = RideMomentsUpdatePayload(moments: moments.enumerated().map { offset, moment in
            SupabaseMomentPayload(moment: moment, fallbackIndex: offset)
        })
        try await client.patch(
            path: "rest/v1/ride_logs",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(ride.id.uuidString)")],
            body: payload,
            accessToken: token
        )
        return payload.moments.map(\.moment)
    }

    func saveFeedback(_ feedback: RideFeedback, for ride: Ride) async throws -> RideFeedback {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        var saved = feedback
        saved.at = Date()
        try await client.patch(
            path: "rest/v1/ride_logs",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(ride.id.uuidString)")],
            body: RideFeedbackUpdatePayload(feedback: saved),
            accessToken: token
        )
        return saved
    }

    func fetchRatedRideFeatures() async throws -> [RatedRideFeatures] {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let rows: [SupabaseRecommendationRideRow] = try await client.get(
            path: "rest/v1/ride_logs",
            queryItems: [
                URLQueryItem(name: "select", value: "ai_features,feedback"),
                URLQueryItem(name: "ai_features", value: "not.is.null"),
                URLQueryItem(name: "feedback", value: "not.is.null"),
                URLQueryItem(name: "order", value: "ride_date.desc"),
                URLQueryItem(name: "limit", value: "100")
            ],
            accessToken: token
        )
        return rows.compactMap(\.ratedFeatures)
    }

    func setSharing(_ isPublic: Bool, for ride: Ride) async throws -> Ride {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let payload = RideShareUpdatePayload(isPublic: isPublic)
        let rows: [SupabaseRideRow] = try await client.patch(
            path: "rest/v1/ride_logs",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(ride.id.uuidString)"),
                URLQueryItem(name: "select", value: Self.rideSelectColumns)
            ],
            body: payload,
            accessToken: token,
            prefer: "return=representation"
        )
        var updated = rows.first?.ride ?? ride
        updated.routePreview = ride.routePreview
        return updated
    }

    private static let rideSelectColumns = "id,title,distance_km,duration_min,elevation_m,ride_date,gpx_path,moments,is_public,share_token,skills,planned_route_id"

    private func downloadTrack(path: String, accessToken: String) async throws -> GPXTrack {
        let data = try await client.download(
            path: "storage/v1/object/gpx-files/\(path)",
            accessToken: accessToken
        )
        return try GPXParser().parse(data: data)
    }

    private func fetchStoredMetadata(for rideID: UUID, accessToken: String) async throws -> SupabaseRideMetadata {
        let query = [
            URLQueryItem(name: "id", value: "eq.\(rideID.uuidString)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        do {
            let rows: [SupabaseRideMetadataRow] = try await client.get(
                path: "rest/v1/ride_logs",
                queryItems: [URLQueryItem(name: "select", value: "moments,feedback")] + query,
                accessToken: accessToken
            )
            return SupabaseRideMetadata(
                moments: rows.first?.moments?.map(\.moment) ?? [],
                feedback: rows.first?.feedback
            )
        } catch {
            // The AI migration is optional during rollout. A missing feedback
            // column must never stop a rider opening an existing ride.
            let rows: [SupabaseRideMomentsFallbackRow] = try await client.get(
                path: "rest/v1/ride_logs",
                queryItems: [URLQueryItem(name: "select", value: "moments")] + query,
                accessToken: accessToken
            )
            return SupabaseRideMetadata(moments: rows.first?.moments?.map(\.moment) ?? [], feedback: nil)
        }
    }

    private func saveCoachSummary(_ summary: RideCoachStorageSummary, for rideID: UUID, accessToken: String) async throws {
        try await client.patch(
            path: "rest/v1/ride_logs",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(rideID.uuidString)")],
            body: RideSkillsUpdatePayload(skills: summary),
            accessToken: accessToken
        )
    }

    private func saveFeatureRecord(_ features: RideFeatureRecord, for rideID: UUID, accessToken: String) async throws {
        try await client.patch(
            path: "rest/v1/ride_logs",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(rideID.uuidString)")],
            body: RideFeatureUpdatePayload(aiFeatures: features, aiVersion: "ride-features-v1"),
            accessToken: accessToken
        )
    }

    private func fetchPastCoachHistory(excluding rideID: UUID, accessToken: String) async throws -> RideCoachHistory {
        let rows: [SupabaseRideSkillsRow] = try await client.get(
            path: "rest/v1/ride_logs",
            queryItems: [
                URLQueryItem(name: "select", value: "id,skills"),
                URLQueryItem(name: "id", value: "neq.\(rideID.uuidString)"),
                URLQueryItem(name: "skills", value: "not.is.null"),
                URLQueryItem(name: "order", value: "ride_date.desc"),
                URLQueryItem(name: "limit", value: "30")
            ],
            accessToken: accessToken
        )
        var scoreValues: [String: [Double]] = [:]
        for row in rows {
            for (key, value) in row.skills?.scores ?? [:] where value.isFinite {
                scoreValues[key, default: []].append(value)
            }
        }
        return RideCoachHistory(
            corners: rows.flatMap { $0.skills?.corners ?? [] },
            averageScores: scoreValues.mapValues { values in
                values.reduce(0, +) / Double(values.count)
            }
        )
    }

    private func fetchPlannedRoute(id: UUID, accessToken: String) async throws -> PlannedRoute? {
        let rows: [SupabaseLinkedPlannedRouteRow] = try await client.get(
            path: "rest/v1/planned_routes",
            queryItems: [
                URLQueryItem(name: "select", value: "id,title,distance_km,elevation_m,waypoints,route,created_at,is_public,share_token"),
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: accessToken
        )
        return rows.first?.plannedRoute
    }
}

private struct RideCoachHistory {
    let corners: [RideCoachCornerSummary]
    let averageScores: [String: Double]

    static let empty = RideCoachHistory(corners: [], averageScores: [:])
}

enum RideServiceError: LocalizedError {
    case notImplemented
    case notAuthenticated
    case sharingUnavailable
    case gpxUnavailable

    var errorDescription: String? {
        switch self {
        case .notImplemented: "Ride syncing isn’t connected yet."
        case .notAuthenticated: "Sign in to sync your rides."
        case .sharingUnavailable: "The ride was shared, but no public link was returned."
        case .gpxUnavailable: "This ride does not have an exportable GPX file."
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

private struct SupabaseRideRow: Decodable {
    let id: UUID
    let title: String?
    let distanceKm: Double?
    let durationMin: Double?
    let elevationM: Double?
    let rideDate: String?
    let gpxPath: String?
    let moments: [SupabaseMoment]?
    let isPublic: Bool?
    let shareToken: UUID?
    let skills: SupabaseSkills?
    let plannedRouteID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case elevationM = "elevation_m"
        case rideDate = "ride_date"
        case gpxPath = "gpx_path"
        case moments
        case isPublic = "is_public"
        case shareToken = "share_token"
        case skills
        case plannedRouteID = "planned_route_id"
    }

    var ride: Ride {
        Ride(
            id: id,
            title: cleanTitle,
            date: parsedDate,
            distanceMeters: (distanceKm ?? 0) * 1000,
            durationSeconds: (durationMin ?? 0) * 60,
            elevationGainMeters: elevationM ?? 0,
            flowScore: skills?.flowScore,
            locationName: nil,
            source: gpxPath == nil ? .live : .gpx,
            routePreview: [],
            gpxPath: gpxPath,
            plannedRouteID: plannedRouteID,
            isPublic: isPublic ?? false,
            shareToken: shareToken
        )
    }

    private var parsedDate: Date {
        SupabaseDate.parse(rideDate) ?? Date()
    }

    private var cleanTitle: String {
        guard let title, !title.isEmpty else { return "Untitled Ride" }
        return title
    }
}

private struct SupabaseMoment: Decodable {
    let note: String?
    let title: String?
    let index: Int?
    let latitude: Double?
    let longitude: Double?
    let speed: Double?
    let elevation: Double?

    enum CodingKeys: String, CodingKey {
        case note
        case title
        case index = "idx"
        case latitude = "lat"
        case longitude = "lng"
        case speed
        case elevation
    }

    var moment: Moment {
        Moment(
            title: title ?? "",
            note: note ?? "",
            coordinate: Coordinate(latitude: latitude ?? 0, longitude: longitude ?? 0),
            routeIndex: index,
            speedKmh: speed,
            elevationMeters: elevation,
            symbol: note?.isEmpty == false ? "note.text" : "mappin.circle.fill"
        )
    }
}

private struct SupabaseSkills: Decodable {
    let scores: [String: Double]?
    let corners: [RideCoachCornerSummary]?

    var flowScore: Int? {
        guard let values = scores?.values.filter({ $0.isFinite }), !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }
}

private struct SupabaseRideMetadataRow: Decodable {
    let moments: [SupabaseMoment]?
    let feedback: RideFeedback?
}

private struct SupabaseRideMomentsFallbackRow: Decodable {
    let moments: [SupabaseMoment]?
}

private struct SupabaseRideMetadata {
    let moments: [Moment]
    let feedback: RideFeedback?
}

private struct SupabaseRideSkillsRow: Decodable {
    let id: UUID
    let skills: SupabaseSkills?
}

private struct RideMomentsUpdatePayload: Encodable {
    let moments: [SupabaseMomentPayload]
}

private struct RideSkillsUpdatePayload: Encodable {
    let skills: RideCoachStorageSummary
}

private struct RideFeatureUpdatePayload: Encodable {
    let aiFeatures: RideFeatureRecord
    let aiVersion: String

    enum CodingKeys: String, CodingKey {
        case aiFeatures = "ai_features"
        case aiVersion = "ai_version"
    }
}

private struct RideFeedbackUpdatePayload: Encodable {
    let feedback: RideFeedback
}

private struct SupabaseRecommendationRideRow: Decodable {
    let aiFeatures: RideFeatureRecord?
    let feedback: RideFeedback?

    enum CodingKeys: String, CodingKey {
        case aiFeatures = "ai_features"
        case feedback
    }

    var ratedFeatures: RatedRideFeatures? {
        guard let aiFeatures, let enjoyment = feedback?.enjoyment else { return nil }
        return RatedRideFeatures(features: aiFeatures, enjoyment: Double(enjoyment))
    }
}

private struct RideShareUpdatePayload: Encodable {
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case isPublic = "is_public"
    }
}

private struct SupabaseLinkedPlannedRouteRow: Decodable {
    let id: UUID
    let title: String?
    let distanceKm: Double?
    let elevationM: Double?
    let waypoints: [LinkedWaypointPayload]?
    let route: [LinkedRouteCoordinatePayload]?
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
        SupabaseDate.parse(createdAt) ?? Date()
    }

    private var cleanTitle: String {
        guard let title, !title.isEmpty else { return "Untitled Route" }
        return title
    }
}

private struct LinkedWaypointPayload: Decodable {
    let lat: Double
    let lng: Double

    var coordinate: Coordinate {
        Coordinate(latitude: lat, longitude: lng)
    }
}

private struct LinkedRouteCoordinatePayload: Decodable {
    let coordinate: Coordinate

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let latitude = try container.decode(Double.self)
        let longitude = try container.decode(Double.self)
        coordinate = Coordinate(latitude: latitude, longitude: longitude)
    }
}

private struct SupabaseMomentPayload: Encodable {
    let index: Int
    let latitude: Double
    let longitude: Double
    let speed: Double?
    let elevation: Double?
    let title: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case index = "idx"
        case latitude = "lat"
        case longitude = "lng"
        case speed
        case elevation
        case title
        case note
    }

    init(moment: Moment, fallbackIndex: Int) {
        index = moment.routeIndex ?? fallbackIndex
        latitude = moment.coordinate.latitude
        longitude = moment.coordinate.longitude
        speed = moment.speedKmh
        elevation = moment.elevationMeters
        title = moment.title
        note = moment.note
    }

    var moment: Moment {
        Moment(
            title: title,
            note: note,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            routeIndex: index,
            speedKmh: speed,
            elevationMeters: elevation,
            symbol: note.isEmpty ? "mappin.circle.fill" : "note.text"
        )
    }
}
