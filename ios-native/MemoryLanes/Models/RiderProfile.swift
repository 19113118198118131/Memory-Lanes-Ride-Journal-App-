import Foundation

struct RiderProfile: Codable, Equatable, Sendable {
    let userID: UUID
    var displayName: String
    var region: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case region
    }
}
