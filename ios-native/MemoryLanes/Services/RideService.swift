import Foundation

// MARK: - RideServing
//
// The services layer is protocol-first so screens depend on an abstraction,
// not a concrete backend. `RideService` will wrap Supabase; `PreviewRideService`
// feeds sample data to previews and tests. Both are injected, never global.

@MainActor
protocol RideServing {
    func fetchRides() async throws -> [Ride]
    /// Full analysis for one ride, loaded when the rider opens it.
    func fetchDetail(for ride: Ride) async throws -> RideDetail
    func saveMoments(_ moments: [Moment], for ride: Ride) async throws -> [Moment]
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
            debrief: SampleData.heroDetail.debrief
        )
    }

    func saveMoments(_ moments: [Moment], for ride: Ride) async throws -> [Moment] {
        try await Task.sleep(for: .milliseconds(250))
        if let failure { throw failure }
        return moments
    }
}

// MARK: - Live implementation

struct RideService: RideServing {
    var accessToken: () -> String?
    private var client = SupabaseHTTPClient()

    init(accessToken: @escaping () -> String?) {
        self.accessToken = accessToken
    }

    func fetchRides() async throws -> [Ride] {
        guard let token = accessToken() else { throw RideServiceError.notAuthenticated }
        let rows: [SupabaseRideRow] = try await client.get(
            path: "rest/v1/ride_logs",
            queryItems: [
                URLQueryItem(name: "select", value: "id,title,distance_km,duration_min,elevation_m,ride_date,gpx_path,moments,is_public,skills,planned_route_id"),
                URLQueryItem(name: "order", value: "ride_date.desc")
            ],
            accessToken: token
        )
        var hydrated: [Ride] = []
        for row in rows {
            var ride = row.ride
            if let gpxPath = row.gpxPath,
               let track = try? await downloadTrack(path: gpxPath, accessToken: token) {
                ride.routePreview = track.routePreview
            }
            hydrated.append(ride)
        }
        return hydrated
    }

    func fetchDetail(for ride: Ride) async throws -> RideDetail {
        guard let token = accessToken() else { throw RideServiceError.notAuthenticated }
        let storedMoments = try await fetchStoredMoments(for: ride.id, accessToken: token)
        guard let gpxPath = ride.gpxPath else {
            return RideDetail(id: ride.id, routePreview: [], replayPoints: [], elevation: [], corners: [], moments: storedMoments, weather: nil, debrief: "This ride does not have an attached GPX file yet.")
        }
        let data = try await client.download(
            path: "storage/v1/object/gpx-files/\(gpxPath)",
            accessToken: token
        )
        let track = try GPXParser().parse(data: data)
        return RideDetail(
            id: ride.id,
            routePreview: track.routePreview,
            replayPoints: track.replayPoints,
            elevation: track.elevationSamples,
            corners: [],
            moments: storedMoments,
            weather: nil,
            debrief: "Route and elevation loaded from the saved GPX. Ride Coach analysis is the next layer."
        )
    }

    func saveMoments(_ moments: [Moment], for ride: Ride) async throws -> [Moment] {
        guard let token = accessToken() else { throw RideServiceError.notAuthenticated }
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

    private func downloadTrack(path: String, accessToken: String) async throws -> GPXTrack {
        let data = try await client.download(
            path: "storage/v1/object/gpx-files/\(path)",
            accessToken: accessToken
        )
        return try GPXParser().parse(data: data)
    }

    private func fetchStoredMoments(for rideID: UUID, accessToken: String) async throws -> [Moment] {
        let rows: [SupabaseRideMomentRow] = try await client.get(
            path: "rest/v1/ride_logs",
            queryItems: [
                URLQueryItem(name: "select", value: "moments"),
                URLQueryItem(name: "id", value: "eq.\(rideID.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: accessToken
        )
        return rows.first?.moments?.map(\.moment) ?? []
    }
}

enum RideServiceError: LocalizedError {
    case notImplemented
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notImplemented: "Ride syncing isn’t connected yet."
        case .notAuthenticated: "Sign in to sync your rides."
        }
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
    let skills: SupabaseSkills?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case elevationM = "elevation_m"
        case rideDate = "ride_date"
        case gpxPath = "gpx_path"
        case moments
        case skills
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
            gpxPath: gpxPath
        )
    }

    private var parsedDate: Date {
        guard let rideDate else { return Date() }
        if let date = ISO8601DateFormatter().date(from: rideDate) { return date }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rideDate) ?? Date()
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

    var flowScore: Int? {
        guard let values = scores?.values.filter({ $0.isFinite }), !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }
}

private struct SupabaseRideMomentRow: Decodable {
    let moments: [SupabaseMoment]?
}

private struct RideMomentsUpdatePayload: Encodable {
    let moments: [SupabaseMomentPayload]
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
