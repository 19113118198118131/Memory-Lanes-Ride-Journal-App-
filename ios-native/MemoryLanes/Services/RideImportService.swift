import Foundation

struct RideImportService {
    private var client = SupabaseHTTPClient()

    func saveImportedRide(
        title: String,
        gpxData: Data,
        track: GPXTrack,
        session: AuthSession
    ) async throws -> Ride {
        let filePath = "\(session.userID.uuidString.lowercased())/\(Int(Date().timeIntervalSince1970 * 1000)).gpx"
        try await client.upload(
            path: "storage/v1/object/gpx-files/\(filePath)",
            data: gpxData,
            contentType: "application/gpx+xml",
            accessToken: session.accessToken
        )

        let payload = RideInsertPayload(
            title: title,
            userID: session.userID,
            distanceKm: track.distanceMeters / 1000,
            durationMin: track.durationSeconds / 60,
            elevationM: track.elevationGainMeters,
            rideDate: track.startedAt,
            gpxPath: filePath
        )

        do {
            let rows: [RideInsertResponse] = try await client.post(
                path: "rest/v1/ride_logs",
                queryItems: [URLQueryItem(name: "select", value: "*")],
                body: payload,
                accessToken: session.accessToken,
                prefer: "return=representation"
            )
            guard let row = rows.first else { throw RideImportError.missingInsertedRide }
            return row.ride(routePreview: track.routePreview)
        } catch {
            try? await deleteUploadedGPX(path: filePath, accessToken: session.accessToken)
            throw error
        }
    }

    func saveRecordedRide(
        title: String,
        result: RecordedRideResult,
        session: AuthSession
    ) async throws -> Ride {
        let gpxData = Data(result.gpxText.utf8)
        let filePath = "\(session.userID.uuidString.lowercased())/recorded-\(Int(Date().timeIntervalSince1970 * 1000)).gpx"
        try await client.upload(
            path: "storage/v1/object/gpx-files/\(filePath)",
            data: gpxData,
            contentType: "application/gpx+xml",
            accessToken: session.accessToken
        )

        let payload = RideInsertPayload(
            title: title,
            userID: session.userID,
            distanceKm: result.distanceMeters / 1000,
            durationMin: result.durationSeconds / 60,
            elevationM: result.elevationGainMeters,
            rideDate: result.startedAt,
            gpxPath: filePath
        )

        do {
            let rows: [RideInsertResponse] = try await client.post(
                path: "rest/v1/ride_logs",
                queryItems: [URLQueryItem(name: "select", value: "*")],
                body: payload,
                accessToken: session.accessToken,
                prefer: "return=representation"
            )
            guard let row = rows.first else { throw RideImportError.missingInsertedRide }
            return row.ride(routePreview: result.points.routePreview, source: .live)
        } catch {
            try? await deleteUploadedGPX(path: filePath, accessToken: session.accessToken)
            throw error
        }
    }

    private func deleteUploadedGPX(path: String, accessToken: String) async throws {
        let payload = StorageDeletePayload(prefixes: [path])
        let _: StorageDeleteResponse = try await client.post(
            path: "storage/v1/object/gpx-files",
            body: payload,
            accessToken: accessToken
        )
    }
}

enum RideImportError: LocalizedError {
    case missingInsertedRide

    var errorDescription: String? {
        switch self {
        case .missingInsertedRide:
            return "The ride was saved, but Supabase did not return it."
        }
    }
}

private struct RideInsertPayload: Encodable {
    let title: String
    let userID: UUID
    let distanceKm: Double
    let durationMin: Double
    let elevationM: Double
    let rideDate: Date
    let gpxPath: String

    enum CodingKeys: String, CodingKey {
        case title
        case userID = "user_id"
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case elevationM = "elevation_m"
        case rideDate = "ride_date"
        case gpxPath = "gpx_path"
    }
}

private struct RideInsertResponse: Decodable {
    let id: UUID
    let title: String?
    let distanceKm: Double?
    let durationMin: Double?
    let elevationM: Double?
    let rideDate: Date?
    let gpxPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case elevationM = "elevation_m"
        case rideDate = "ride_date"
        case gpxPath = "gpx_path"
    }

    func ride(routePreview: [Coordinate], source: RideSource? = nil) -> Ride {
        Ride(
            id: id,
            title: cleanTitle,
            date: rideDate ?? Date(),
            distanceMeters: (distanceKm ?? 0) * 1000,
            durationSeconds: (durationMin ?? 0) * 60,
            elevationGainMeters: elevationM ?? 0,
            source: source ?? (gpxPath == nil ? .live : .gpx),
            routePreview: routePreview,
            gpxPath: gpxPath
        )
    }

    private var cleanTitle: String {
        guard let title, !title.isEmpty else { return "Imported Ride" }
        return title
    }
}

private struct StorageDeletePayload: Encodable {
    let prefixes: [String]
}

private struct StorageDeleteResponse: Decodable {}
