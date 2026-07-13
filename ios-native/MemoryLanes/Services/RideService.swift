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
    func fetchDetail(for rideID: UUID) async throws -> RideDetail
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

    func fetchDetail(for rideID: UUID) async throws -> RideDetail {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        // Sample detail is keyed to the hero ride; reuse its analysis with the
        // requested id so any previewed ride resolves to something to show.
        return RideDetail(
            id: rideID,
            elevation: SampleData.heroDetail.elevation,
            corners: SampleData.heroDetail.corners,
            moments: SampleData.heroDetail.moments,
            weather: SampleData.heroDetail.weather,
            debrief: SampleData.heroDetail.debrief
        )
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
        return rows.map(\.ride)
    }

    func fetchDetail(for rideID: UUID) async throws -> RideDetail {
        // Detail analysis still needs the GPX parser and Ride Coach port. Return a
        // graceful empty detail for live rows so Ride Detail opens from real data.
        RideDetail(id: rideID, elevation: [], corners: [], moments: [], weather: nil, debrief: "Detailed replay and coaching will appear here once GPX parsing lands.")
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
            routePreview: []
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
}

private struct SupabaseSkills: Decodable {
    let scores: [String: Double]?

    var flowScore: Int? {
        guard let values = scores?.values.filter({ $0.isFinite }), !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }
}
