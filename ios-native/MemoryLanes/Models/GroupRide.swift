import Foundation

enum GroupRideRSVP: String, Codable, CaseIterable, Hashable, Sendable {
    case going
    case maybe
    case no

    var title: String {
        switch self {
        case .going: "Riding"
        case .maybe: "Maybe"
        case .no: "Not this time"
        }
    }

    var symbol: String {
        switch self {
        case .going: "checkmark.circle.fill"
        case .maybe: "questionmark.circle.fill"
        case .no: "xmark.circle.fill"
        }
    }
}

struct GroupRideMember: Codable, Hashable, Sendable {
    let name: String
    let rsvp: GroupRideRSVP
    let isYou: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case rsvp
        case isYou = "is_you"
    }
}

struct GroupRideSummary: Identifiable, Codable, Hashable, Sendable {
    let title: String
    let shareToken: UUID
    let meetTime: Date?
    let meetPoint: String?
    let createdAt: Date
    let isOwner: Bool
    let memberCount: Int
    let routeTitle: String

    var id: UUID { shareToken }
    var inviteURL: URL? { GroupRide.inviteURL(for: shareToken) }

    enum CodingKeys: String, CodingKey {
        case title
        case shareToken = "share_token"
        case meetTime = "meet_time"
        case meetPoint = "meet_point"
        case createdAt = "created_at"
        case isOwner = "is_owner"
        case memberCount = "member_count"
        case routeTitle = "route_title"
    }
}

struct GroupRide: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var isActive: Bool
    let createdAt: Date
    var meetTime: Date?
    var meetPoint: String?
    let hostedBy: String?
    var memberCount: Int
    let isOwner: Bool
    var isMember: Bool
    var yourRSVP: GroupRideRSVP?
    var members: [GroupRideMember]
    let routeID: UUID
    let routeTitle: String
    let distanceKm: Double?
    let elevationM: Double?
    let route: [Coordinate]
    let shareToken: UUID

    var inviteURL: URL? { Self.inviteURL(for: shareToken) }

    var plannedRoute: PlannedRoute {
        PlannedRoute(
            id: routeID,
            title: routeTitle,
            distanceKm: distanceKm,
            elevationM: elevationM,
            waypoints: route.first.map { [$0, route.last ?? $0] } ?? [],
            route: route,
            createdAt: createdAt,
            isPublic: false,
            shareToken: nil
        )
    }

    static func inviteURL(for token: UUID) -> URL? {
        URL(string: "https://memory-lanes-ride-journal-app.vercel.app/group.html?ride=\(token.uuidString)")
    }
}

struct GroupRidePayload: Decodable, Sendable {
    let id: UUID
    let title: String
    let isActive: Bool
    let createdAt: Date
    let meetTime: Date?
    let meetPoint: String?
    let hostedBy: String?
    let memberCount: Int
    let isOwner: Bool
    let isMember: Bool
    let yourRSVP: GroupRideRSVP?
    let members: [GroupRideMember]
    let routeID: UUID
    let routeTitle: String
    let distanceKm: Double?
    let elevationM: Double?
    let route: [GroupRideCoordinatePayload]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isActive = "is_active"
        case createdAt = "created_at"
        case meetTime = "meet_time"
        case meetPoint = "meet_point"
        case hostedBy = "hosted_by"
        case memberCount = "member_count"
        case isOwner = "is_owner"
        case isMember = "is_member"
        case yourRSVP = "your_rsvp"
        case members
        case routeID = "route_id"
        case routeTitle = "route_title"
        case distanceKm = "distance_km"
        case elevationM = "elevation_m"
        case route
    }

    func groupRide(shareToken: UUID) -> GroupRide {
        GroupRide(
            id: id,
            title: title,
            isActive: isActive,
            createdAt: createdAt,
            meetTime: meetTime,
            meetPoint: meetPoint,
            hostedBy: hostedBy,
            memberCount: memberCount,
            isOwner: isOwner,
            isMember: isMember,
            yourRSVP: yourRSVP,
            members: members,
            routeID: routeID,
            routeTitle: routeTitle,
            distanceKm: distanceKm,
            elevationM: elevationM,
            route: route.map(\.coordinate),
            shareToken: shareToken
        )
    }
}

struct GroupRideCoordinatePayload: Decodable, Sendable {
    let coordinate: Coordinate

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        coordinate = Coordinate(
            latitude: try container.decode(Double.self),
            longitude: try container.decode(Double.self)
        )
    }
}
