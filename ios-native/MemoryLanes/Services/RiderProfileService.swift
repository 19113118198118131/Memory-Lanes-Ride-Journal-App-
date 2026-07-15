import Foundation

protocol RiderProfileServing: Sendable {
    func fetchProfile() async throws -> RiderProfile?
    func saveProfile(displayName: String, region: String) async throws -> RiderProfile
}

struct RiderProfileService: RiderProfileServing, Sendable {
    var client = SupabaseHTTPClient()
    var accessToken: @Sendable () async -> String?
    var userID: UUID

    func fetchProfile() async throws -> RiderProfile? {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let rows: [RiderProfile] = try await client.get(
            path: "rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "user_id,display_name,region"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
            ],
            accessToken: token
        )
        return rows.first
    }

    func saveProfile(displayName: String, region: String) async throws -> RiderProfile {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let rows: [RiderProfile] = try await client.post(
            path: "rest/v1/profiles",
            queryItems: [URLQueryItem(name: "on_conflict", value: "user_id")],
            body: RiderProfile(
                userID: userID,
                displayName: displayName,
                region: region
            ),
            accessToken: token,
            prefer: "resolution=merge-duplicates,return=representation"
        )
        guard let profile = rows.first else { throw RiderProfileServiceError.missingProfile }
        return profile
    }
}

enum RiderProfileServiceError: LocalizedError {
    case missingProfile

    var errorDescription: String? {
        "Your rider profile was saved, but could not be reloaded. Refresh and try again."
    }
}
