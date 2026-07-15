import Foundation

struct RideImportService {
    private var client = SupabaseHTTPClient()
    private var localStore: any RideLocalStoring = RideLocalStore.shared

    func saveImportedRide(
        title: String,
        gpxData: Data,
        track: GPXTrack,
        userID: UUID,
        accessToken: String
    ) async throws -> Ride {
        let filePath = "\(userID.uuidString.lowercased())/\(Int(Date().timeIntervalSince1970 * 1000)).gpx"
        try await client.upload(
            path: "storage/v1/object/gpx-files/\(filePath)",
            data: gpxData,
            contentType: "application/gpx+xml",
            accessToken: accessToken
        )

        let payload = RideInsertPayload(
            title: title,
            userID: userID,
            distanceKm: track.distanceMeters / 1000,
            durationMin: track.durationSeconds / 60,
            elevationM: track.elevationGainMeters,
            rideDate: track.startedAt,
            gpxPath: filePath,
            plannedRouteID: nil
        )

        do {
            let rows: [RideInsertResponse] = try await client.post(
                path: "rest/v1/ride_logs",
                queryItems: [URLQueryItem(name: "select", value: "*")],
                body: payload,
                accessToken: accessToken,
                prefer: "return=representation"
            )
            guard let row = rows.first else { throw RideImportError.missingInsertedRide }
            let ride = row.ride(routePreview: track.routePreview)
            try? await localStore.upsert(ride, gpxData: gpxData, for: userID)
            return ride
        } catch {
            try? await deleteUploadedGPX(path: filePath, accessToken: accessToken)
            throw error
        }
    }

    func saveRecordedRide(
        title: String,
        result: RecordedRideResult,
        plannedRouteID: UUID? = nil,
        userID: UUID,
        accessToken: String
    ) async throws -> Ride {
        let gpxData = Data(result.gpxText.utf8)
        let filePath = "\(userID.uuidString.lowercased())/recorded-\(Int(Date().timeIntervalSince1970 * 1000)).gpx"
        try await client.upload(
            path: "storage/v1/object/gpx-files/\(filePath)",
            data: gpxData,
            contentType: "application/gpx+xml",
            accessToken: accessToken
        )

        let payload = RideInsertPayload(
            title: title,
            userID: userID,
            distanceKm: result.distanceMeters / 1000,
            durationMin: result.durationSeconds / 60,
            elevationM: result.elevationGainMeters,
            rideDate: result.startedAt,
            gpxPath: filePath,
            plannedRouteID: plannedRouteID
        )

        do {
            let rows: [RideInsertResponse] = try await client.post(
                path: "rest/v1/ride_logs",
                queryItems: [URLQueryItem(name: "select", value: "*")],
                body: payload,
                accessToken: accessToken,
                prefer: "return=representation"
            )
            guard let row = rows.first else { throw RideImportError.missingInsertedRide }
            let ride = row.ride(routePreview: result.points.routePreview, source: .live)
            try? await localStore.upsert(ride, gpxData: gpxData, for: userID)
            return ride
        } catch {
            try? await deleteUploadedGPX(path: filePath, accessToken: accessToken)
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
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .missingInsertedRide:
            return "The ride was saved, but Supabase did not return it."
        case .notAuthenticated:
            return "Your session expired. Sign in again to save this ride; the local recording is still safe."
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
    let plannedRouteID: UUID?

    enum CodingKeys: String, CodingKey {
        case title
        case userID = "user_id"
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case elevationM = "elevation_m"
        case rideDate = "ride_date"
        case gpxPath = "gpx_path"
        case plannedRouteID = "planned_route_id"
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
    let plannedRouteID: UUID?
    let isPublic: Bool?
    let shareToken: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case elevationM = "elevation_m"
        case rideDate = "ride_date"
        case gpxPath = "gpx_path"
        case plannedRouteID = "planned_route_id"
        case isPublic = "is_public"
        case shareToken = "share_token"
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
            gpxPath: gpxPath,
            plannedRouteID: plannedRouteID,
            isPublic: isPublic ?? false,
            shareToken: shareToken
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
