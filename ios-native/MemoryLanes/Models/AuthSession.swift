import Foundation

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: UUID
    let email: String?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}
