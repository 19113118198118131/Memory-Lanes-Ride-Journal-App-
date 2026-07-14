import Foundation

@MainActor
protocol JournalServing {
    func fetchEntries() async throws -> [JournalEntry]
}

struct PreviewJournalService: JournalServing {
    var entries: [JournalEntry] = SampleData.journalEntries
    var failure: RideServiceError? = nil
    var delay: Duration = .milliseconds(300)

    func fetchEntries() async throws -> [JournalEntry] {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        return entries
    }
}

struct JournalService: JournalServing {
    var client = SupabaseHTTPClient()
    var accessToken: () -> String?

    func fetchEntries() async throws -> [JournalEntry] {
        guard let token = accessToken() else { throw RideServiceError.notAuthenticated }
        let rows: [JournalRideRow] = try await client.get(
            path: "rest/v1/ride_logs",
            queryItems: [
                URLQueryItem(name: "select", value: "id,title,distance_km,duration_min,elevation_m,ride_date,gpx_path,moments,skills"),
                URLQueryItem(name: "order", value: "ride_date.desc")
            ],
            accessToken: token
        )

        return rows.flatMap(\.journalEntries)
            .sorted { lhs, rhs in
                if lhs.rideDate != rhs.rideDate { return lhs.rideDate > rhs.rideDate }
                return lhs.index > rhs.index
            }
    }
}

private struct JournalRideRow: Decodable {
    let id: UUID
    let title: String?
    let distanceKm: Double?
    let durationMin: Double?
    let elevationM: Double?
    let rideDate: String?
    let gpxPath: String?
    let moments: [JournalMomentPayload]?
    let skills: SupabaseSkillsPayload?

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

    var journalEntries: [JournalEntry] {
        guard let moments else { return [] }
        let ride = Ride(
            id: id,
            title: cleanTitle,
            date: parsedDate,
            distanceMeters: (distanceKm ?? 0) * 1000,
            durationSeconds: (durationMin ?? 0) * 60,
            elevationGainMeters: elevationM ?? 0,
            flowScore: skills?.flowScore,
            source: gpxPath == nil ? .live : .gpx,
            gpxPath: gpxPath
        )

        return moments.enumerated().compactMap { offset, moment in
            guard moment.hasContent else { return nil }
            let index = moment.index ?? offset
            return JournalEntry(
                id: "\(id.uuidString)-\(index)-\(offset)",
                title: moment.title ?? "",
                note: moment.note ?? "",
                ride: ride,
                rideDate: parsedDate,
                index: index,
                coordinate: moment.coordinate,
                speedKmh: moment.speed,
                elevationMeters: moment.elevation
            )
        }
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

private struct JournalMomentPayload: Decodable {
    let index: Int?
    let title: String?
    let note: String?
    let latitude: Double?
    let longitude: Double?
    let speed: Double?
    let elevation: Double?

    enum CodingKeys: String, CodingKey {
        case index = "idx"
        case title
        case note
        case latitude = "lat"
        case longitude = "lng"
        case speed
        case elevation
    }

    var hasContent: Bool {
        !(title ?? "").isEmpty || !(note ?? "").isEmpty || coordinate != nil
    }

    var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

private struct SupabaseSkillsPayload: Decodable {
    let scores: [String: Double]?

    var flowScore: Int? {
        guard let values = scores?.values.filter({ $0.isFinite }), !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }
}
