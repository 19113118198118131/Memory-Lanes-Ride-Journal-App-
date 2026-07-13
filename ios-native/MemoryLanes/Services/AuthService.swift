import Foundation

struct AuthService {
    private var client = SupabaseHTTPClient()

    func signIn(email: String, password: String) async throws -> AuthSession {
        let response: AuthResponse = try await client.post(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            body: AuthRequest(email: email, password: password)
        )
        return response.session
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        let response: AuthResponse = try await client.post(
            path: "auth/v1/signup",
            body: AuthRequest(email: email, password: password)
        )
        return response.session
    }
}

private struct AuthRequest: Encodable {
    let email: String
    let password: String
}

private struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let user: AuthUser

    var session: AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userID: user.id,
            email: user.email
        )
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct AuthUser: Decodable {
    let id: UUID
    let email: String?
}
