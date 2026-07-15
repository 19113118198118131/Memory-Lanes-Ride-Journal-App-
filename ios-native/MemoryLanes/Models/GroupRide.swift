import Foundation

enum GroupRideStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case scheduled
    case cancelled
    case completed

    var title: String {
        switch self {
        case .scheduled: "Upcoming"
        case .cancelled: "Cancelled"
        case .completed: "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .scheduled: "calendar.badge.clock"
        case .cancelled: "xmark.circle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }
}

enum GroupRideVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case inviteOnly = "invite_only"
    case community

    var title: String {
        switch self {
        case .inviteOnly: "Invite only"
        case .community: "Community"
        }
    }

    var detail: String {
        switch self {
        case .inviteOnly: "Only riders with your link can find this ride."
        case .community: "Signed-in riders can discover this ride in Memory Lanes."
        }
    }

    var symbol: String {
        switch self {
        case .inviteOnly: "link"
        case .community: "person.3.fill"
        }
    }
}

struct GroupRideDraft: Equatable, Sendable {
    var title: String
    var details: String?
    var meetTime: Date?
    var meetPoint: String?
    var visibility: GroupRideVisibility
    var capacity: Int?
}

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
    let checkedInAt: Date?

    enum CodingKeys: String, CodingKey {
        case name
        case rsvp
        case isYou = "is_you"
        case checkedInAt = "checked_in_at"
    }
}

struct GroupRideAnnouncement: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let message: String
    let createdAt: Date
    let authorName: String
    let isHost: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case message
        case createdAt = "created_at"
        case authorName = "author_name"
        case isHost = "is_host"
    }
}

struct GroupRideSummary: Identifiable, Codable, Hashable, Sendable {
    let title: String
    let details: String?
    let visibility: GroupRideVisibility?
    let capacity: Int?
    let status: GroupRideStatus?
    let shareToken: UUID
    let meetTime: Date?
    let meetPoint: String?
    let createdAt: Date
    let isOwner: Bool
    let yourRSVP: GroupRideRSVP?
    let memberCount: Int
    let goingCount: Int?
    let maybeCount: Int?
    let declinedCount: Int?
    let routeTitle: String

    var id: UUID { shareToken }
    var inviteURL: URL? { GroupRide.inviteURL(for: shareToken) }

    enum CodingKeys: String, CodingKey {
        case title
        case details
        case visibility
        case capacity
        case status
        case shareToken = "share_token"
        case meetTime = "meet_time"
        case meetPoint = "meet_point"
        case createdAt = "created_at"
        case isOwner = "is_owner"
        case yourRSVP = "your_rsvp"
        case memberCount = "member_count"
        case goingCount = "going_count"
        case maybeCount = "maybe_count"
        case declinedCount = "declined_count"
        case routeTitle = "route_title"
    }
}

struct CommunityGroupRideSummary: Identifiable, Codable, Hashable, Sendable {
    let title: String
    let details: String?
    let shareToken: UUID
    let meetTime: Date?
    let hostedBy: String?
    let hostRegion: String?
    let capacity: Int?
    let goingCount: Int
    let maybeCount: Int
    let routeTitle: String
    let distanceKm: Double?
    let elevationM: Double?

    var id: UUID { shareToken }
    var spotsRemaining: Int? { capacity.map { max($0 - goingCount, 0) } }
    var isFull: Bool { spotsRemaining == 0 }

    enum CodingKeys: String, CodingKey {
        case title
        case details
        case shareToken = "share_token"
        case meetTime = "meet_time"
        case hostedBy = "hosted_by"
        case hostRegion = "host_region"
        case capacity
        case goingCount = "going_count"
        case maybeCount = "maybe_count"
        case routeTitle = "route_title"
        case distanceKm = "distance_km"
        case elevationM = "elevation_m"
    }
}

struct GroupRide: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var details: String?
    var visibility: GroupRideVisibility
    var capacity: Int?
    var status: GroupRideStatus
    var isActive: Bool
    let createdAt: Date
    var meetTime: Date?
    var meetPoint: String?
    let hostedBy: String?
    var memberCount: Int
    var goingCount: Int
    var maybeCount: Int
    var declinedCount: Int
    let isOwner: Bool
    var isMember: Bool
    var yourRSVP: GroupRideRSVP?
    var members: [GroupRideMember]
    var checkedInCount: Int
    var yourCheckedInAt: Date?
    var checkInAvailable: Bool
    var announcements: [GroupRideAnnouncement]
    let routeID: UUID
    let routeTitle: String
    let distanceKm: Double?
    let elevationM: Double?
    let route: [Coordinate]
    let shareToken: UUID

    var inviteURL: URL? { Self.inviteURL(for: shareToken) }

    var spotsRemaining: Int? { capacity.map { max($0 - goingCount, 0) } }
    var isFull: Bool { spotsRemaining == 0 }
    var isCheckedIn: Bool { yourCheckedInAt != nil }

    var withoutMembership: GroupRide {
        var copy = self
        copy.isMember = false
        copy.yourRSVP = nil
        return copy
    }

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

struct GroupRideInvite: Hashable, Sendable {
    let shareToken: UUID

    static func parse(_ url: URL) -> GroupRideInvite? {
        if url.scheme?.lowercased() == "memorylanes" {
            let tokenText = url.host?.lowercased() == "group"
                ? url.pathComponents.dropFirst().first
                : nil
            guard let tokenText, let token = UUID(uuidString: tokenText) else { return nil }
            return GroupRideInvite(shareToken: token)
        }

        guard url.host?.lowercased() == "memory-lanes-ride-journal-app.vercel.app",
              url.path.lowercased().hasSuffix("/group.html"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let tokenText = components.queryItems?.first(where: { $0.name == "ride" })?.value,
              let token = UUID(uuidString: tokenText) else {
            return nil
        }
        return GroupRideInvite(shareToken: token)
    }
}

struct GroupRidePayload: Decodable, Sendable {
    let id: UUID
    let title: String
    let details: String?
    let visibility: GroupRideVisibility?
    let capacity: Int?
    let status: GroupRideStatus?
    let isActive: Bool
    let createdAt: Date
    let meetTime: Date?
    let meetPoint: String?
    let hostedBy: String?
    let memberCount: Int
    let goingCount: Int?
    let maybeCount: Int?
    let declinedCount: Int?
    let isOwner: Bool
    let isMember: Bool
    let yourRSVP: GroupRideRSVP?
    let members: [GroupRideMember]
    let checkedInCount: Int?
    let yourCheckedInAt: Date?
    let checkInAvailable: Bool?
    let announcements: [GroupRideAnnouncement]?
    let routeID: UUID
    let routeTitle: String
    let distanceKm: Double?
    let elevationM: Double?
    let route: [GroupRideCoordinatePayload]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case details
        case visibility
        case capacity
        case status
        case isActive = "is_active"
        case createdAt = "created_at"
        case meetTime = "meet_time"
        case meetPoint = "meet_point"
        case hostedBy = "hosted_by"
        case memberCount = "member_count"
        case goingCount = "going_count"
        case maybeCount = "maybe_count"
        case declinedCount = "declined_count"
        case isOwner = "is_owner"
        case isMember = "is_member"
        case yourRSVP = "your_rsvp"
        case members
        case checkedInCount = "checked_in_count"
        case yourCheckedInAt = "your_checked_in_at"
        case checkInAvailable = "check_in_available"
        case announcements
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
            details: details,
            visibility: visibility ?? .inviteOnly,
            capacity: capacity,
            status: status ?? (isActive ? .scheduled : .completed),
            isActive: isActive,
            createdAt: createdAt,
            meetTime: meetTime,
            meetPoint: meetPoint,
            hostedBy: hostedBy,
            memberCount: memberCount,
            goingCount: goingCount ?? members.filter { $0.rsvp == .going }.count,
            maybeCount: maybeCount ?? members.filter { $0.rsvp == .maybe }.count,
            declinedCount: declinedCount ?? members.filter { $0.rsvp == .no }.count,
            isOwner: isOwner,
            isMember: isMember,
            yourRSVP: yourRSVP,
            members: members,
            checkedInCount: checkedInCount ?? members.filter { $0.checkedInAt != nil }.count,
            yourCheckedInAt: yourCheckedInAt,
            checkInAvailable: checkInAvailable ?? false,
            announcements: announcements ?? [],
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
