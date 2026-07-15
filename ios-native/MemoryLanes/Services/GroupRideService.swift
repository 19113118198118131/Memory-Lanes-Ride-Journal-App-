import Foundation

protocol GroupRideServing: Sendable {
    func fetchMyGroupRides() async throws -> [GroupRideSummary]
    func fetchCommunityGroupRides() async throws -> [CommunityGroupRideSummary]
    func fetchGroupRide(shareToken: UUID) async throws -> GroupRide
    func createGroupRide(route: PlannedRoute, draft: GroupRideDraft) async throws -> GroupRide
    func updateGroupRide(shareToken: UUID, groupRideID: UUID, draft: GroupRideDraft) async throws -> GroupRide
    func setRSVP(_ rsvp: GroupRideRSVP, shareToken: UUID) async throws -> GroupRide
    func leaveGroupRide(shareToken: UUID) async throws
    func setStatus(_ status: GroupRideStatus, shareToken: UUID) async throws -> GroupRide
}

struct GroupRideService: GroupRideServing, Sendable {
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

    func fetchCommunityGroupRides() async throws -> [CommunityGroupRideSummary] {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        return try await client.post(
            path: "rest/v1/rpc/discover_group_rides",
            body: GroupRideDiscoveryPayload(maxResults: 20),
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

    func createGroupRide(route: PlannedRoute, draft: GroupRideDraft) async throws -> GroupRide {
        guard let token = await accessToken(), let userID else { throw RideServiceError.notAuthenticated }
        let rows: [CreatedGroupRideRow] = try await client.post(
            path: "rest/v1/group_rides",
            queryItems: [URLQueryItem(name: "select", value: "id,share_token")],
            body: CreateGroupRidePayload(
                routeID: route.id,
                ownerID: userID,
                title: draft.title,
                details: draft.details,
                meetTime: draft.meetTime,
                meetPoint: draft.meetPoint,
                visibility: draft.visibility,
                capacity: draft.capacity
            ),
            accessToken: token,
            prefer: "return=representation"
        )
        guard let created = rows.first else { throw GroupRideServiceError.missingCreatedRide }
        return try await fetchGroupRide(shareToken: created.shareToken)
    }

    func updateGroupRide(
        shareToken: UUID,
        groupRideID: UUID,
        draft: GroupRideDraft
    ) async throws -> GroupRide {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        try await client.patch(
            path: "rest/v1/group_rides",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(groupRideID.uuidString)")],
            body: GroupRideUpdatePayload(draft: draft),
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

    func leaveGroupRide(shareToken: UUID) async throws {
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let didLeave: Bool = try await client.post(
            path: "rest/v1/rpc/leave_group_ride",
            body: GroupRideTokenPayload(token: shareToken),
            accessToken: token
        )
        guard didLeave else { throw GroupRideServiceError.operationFailed }
    }

    func setStatus(_ status: GroupRideStatus, shareToken: UUID) async throws -> GroupRide {
        guard status != .scheduled else { throw GroupRideServiceError.operationFailed }
        guard let token = await accessToken() else { throw RideServiceError.notAuthenticated }
        let payload: GroupRidePayload? = try await client.post(
            path: "rest/v1/rpc/set_group_ride_status",
            body: GroupRideStatusPayload(token: shareToken, newStatus: status),
            accessToken: token
        )
        guard let payload else { throw GroupRideServiceError.operationFailed }
        return payload.groupRide(shareToken: shareToken)
    }
}

enum GroupRideServiceError: LocalizedError {
    case unavailable
    case missingCreatedRide
    case operationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "This group ride is no longer available. Ask the host for a current invite."
        case .missingCreatedRide:
            "The group ride was created, but Supabase did not return its invite."
        case .operationFailed:
            "That group ride change could not be completed. Refresh and try again."
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

private struct GroupRideDiscoveryPayload: Encodable {
    let maxResults: Int

    enum CodingKeys: String, CodingKey {
        case maxResults = "max_results"
    }
}

private struct GroupRideStatusPayload: Encodable {
    let token: UUID
    let newStatus: GroupRideStatus

    enum CodingKeys: String, CodingKey {
        case token
        case newStatus = "new_status"
    }
}

private struct CreateGroupRidePayload: Encodable {
    let routeID: UUID
    let ownerID: UUID
    let title: String
    let details: String?
    let meetTime: Date?
    let meetPoint: String?
    let visibility: GroupRideVisibility
    let capacity: Int?

    enum CodingKeys: String, CodingKey {
        case routeID = "route_id"
        case ownerID = "owner_id"
        case title
        case details
        case meetTime = "meet_time"
        case meetPoint = "meet_point"
        case visibility
        case capacity
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

private struct GroupRideUpdatePayload: Encodable {
    let title: String
    let details: String?
    let meetTime: Date?
    let meetPoint: String?
    let visibility: GroupRideVisibility
    let capacity: Int?

    init(draft: GroupRideDraft) {
        title = draft.title
        details = draft.details
        meetTime = draft.meetTime
        meetPoint = draft.meetPoint
        visibility = draft.visibility
        capacity = draft.capacity
    }

    enum CodingKeys: String, CodingKey {
        case title
        case details
        case meetTime = "meet_time"
        case meetPoint = "meet_point"
        case visibility
        case capacity
    }
}
