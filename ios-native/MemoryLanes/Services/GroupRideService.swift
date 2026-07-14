import Foundation

@MainActor
protocol GroupRideServing {
    func fetchMyGroupRides() async throws -> [GroupRideSummary]
    func fetchGroupRide(shareToken: UUID) async throws -> GroupRide
    func createGroupRide(
        route: PlannedRoute,
        title: String,
        meetTime: Date?,
        meetPoint: String?
    ) async throws -> GroupRide
    func updateMeeting(shareToken: UUID, groupRideID: UUID, meetTime: Date?, meetPoint: String?) async throws -> GroupRide
    func setRSVP(_ rsvp: GroupRideRSVP, shareToken: UUID) async throws -> GroupRide
    func endGroupRide(_ groupRide: GroupRide) async throws
}

struct GroupRideService: GroupRideServing {
    var client = SupabaseHTTPClient()
    var accessToken: @Sendable () async -> String?
    var userID: UUID?

    func fetchMyGroupRides() async throws -> [GroupRideSummary] {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        return try await client.post(
            path: "rest/v1/rpc/get_my_group_rides",
            body: EmptyPayload(),
            accessToken: token
        )
    }

    func fetchGroupRide(shareToken: UUID) async throws -> GroupRide {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let payload: GroupRidePayload? = try await client.post(
            path: "rest/v1/rpc/get_group_ride",
            body: GroupRideTokenPayload(token: shareToken),
            accessToken: token
        )
        guard let payload else { throw GroupRideServiceError.unavailable }
        return payload.groupRide(shareToken: shareToken)
    }

    func createGroupRide(
        route: PlannedRoute,
        title: String,
        meetTime: Date?,
        meetPoint: String?
    ) async throws -> GroupRide {
        guard let token = await accessToken(), let userID else { throw RideServiceError.notAuthenticated }
        let rows: [CreatedGroupRideRow] = try await client.post(
            path: "rest/v1/group_rides",
            queryItems: [URLQueryItem(name: "select", value: "id,share_token")],
            body: CreateGroupRidePayload(
                routeID: route.id,
                ownerID: userID,
                title: title,
                meetTime: meetTime,
                meetPoint: meetPoint
            ),
            accessToken: token,
            prefer: "return=representation"
        )
        guard let created = rows.first else { throw GroupRideServiceError.missingCreatedRide }
        return try await fetchGroupRide(shareToken: created.shareToken)
    }

    func updateMeeting(
        shareToken: UUID,
        groupRideID: UUID,
        meetTime: Date?,
        meetPoint: String?
    ) async throws -> GroupRide {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        try await client.patch(
            path: "rest/v1/group_rides",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(groupRideID.uuidString)")],
            body: GroupRideMeetingPayload(meetTime: meetTime, meetPoint: meetPoint),
            accessToken: token
        )
        return try await fetchGroupRide(shareToken: shareToken)
    }

    func setRSVP(_ rsvp: GroupRideRSVP, shareToken: UUID) async throws -> GroupRide {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let payload: GroupRidePayload? = try await client.post(
            path: "rest/v1/rpc/rsvp_group_ride",
            body: GroupRideRSVPPayload(token: shareToken, answer: rsvp.rawValue),
            accessToken: token
        )
        guard let payload else { throw GroupRideServiceError.unavailable }
        return payload.groupRide(shareToken: shareToken)
    }

    func endGroupRide(_ groupRide: GroupRide) async throws {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        try await client.patch(
            path: "rest/v1/group_rides",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(groupRide.id.uuidString)")],
            body: EndGroupRidePayload(isActive: false),
            accessToken: token
        )
    }
}

enum GroupRideServiceError: LocalizedError {
    case unavailable
    case missingCreatedRide

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "This group ride is no longer available. Ask the host for a current invite."
        case .missingCreatedRide:
            "The group ride was created, but Supabase did not return its invite."
        }
    }
}

private struct EmptyPayload: Encodable {}

private struct GroupRideTokenPayload: Encodable {
    let token: UUID
}

private struct GroupRideRSVPPayload: Encodable {
    let token: UUID
    let answer: String
}

private struct CreateGroupRidePayload: Encodable {
    let routeID: UUID
    let ownerID: UUID
    let title: String
    let meetTime: Date?
    let meetPoint: String?

    enum CodingKeys: String, CodingKey {
        case routeID = "route_id"
        case ownerID = "owner_id"
        case title
        case meetTime = "meet_time"
        case meetPoint = "meet_point"
    }
}

private struct CreatedGroupRideRow: Decodable {
    let id: UUID
    let shareToken: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case shareToken = "share_token"
    }
}

private struct GroupRideMeetingPayload: Encodable {
    let meetTime: Date?
    let meetPoint: String?

    enum CodingKeys: String, CodingKey {
        case meetTime = "meet_time"
        case meetPoint = "meet_point"
    }
}

private struct EndGroupRidePayload: Encodable {
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
    }
}
