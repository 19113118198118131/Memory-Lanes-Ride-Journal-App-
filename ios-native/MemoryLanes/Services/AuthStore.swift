import Combine
import Foundation

@MainActor
final class AuthStore: ObservableObject {
    enum State: Equatable {
        case checking
        case signedOut
        case signedIn(AuthSession)
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let authService = AuthService()
    private let keychain = KeychainSessionStore()
    /// In-flight refresh, so concurrent callers coalesce onto one network call
    /// instead of racing (a race would burn the rotated refresh token and sign
    /// the user out spuriously).
    private var refreshTask: Task<AuthSession?, Never>?

    init() {
        if let session = keychain.load() {
            if session.isExpired {
                // Token lapsed since last launch — try to refresh before falling
                // back to the sign-in screen, so sessions outlive the ~1h expiry.
                state = .checking
                Task { await self.refreshOnLaunch(session) }
            } else {
                state = .signedIn(session)
            }
        } else {
            state = .signedOut
        }
    }

    var accessToken: String? {
        if case .signedIn(let session) = state { return session.accessToken }
        return nil
    }

    /// Returns a non-expired access token, refreshing first if the current one
    /// is at or near expiry. This is the token provider injected into services,
    /// so every request transparently carries a valid token.
    func validAccessToken() async -> String? {
        guard case .signedIn(let session) = state else { return nil }
        if !session.isExpired { return session.accessToken }
        return await performRefresh(using: session.refreshToken)?.accessToken
    }

    var session: AuthSession? {
        if case .signedIn(let session) = state { return session }
        return nil
    }

    var email: String? {
        if case .signedIn(let session) = state { return session.email }
        return nil
    }

    var userID: UUID? {
        if case .signedIn(let session) = state { return session.userID }
        return nil
    }

    func signIn(email: String, password: String) async {
        await authenticate {
            try await authService.signIn(email: email, password: password)
        }
    }

    func signUp(email: String, password: String) async {
        await authenticate {
            try await authService.signUp(email: email, password: password)
        }
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        keychain.clear()
        state = .signedOut
    }

    private func refreshOnLaunch(_ session: AuthSession) async {
        _ = await performRefresh(using: session.refreshToken)
    }

    /// Refreshes the session, coalescing concurrent callers onto a single
    /// request and persisting the rotated tokens on success. On failure the
    /// session is cleared and the user is returned to sign-in.
    private func performRefresh(using refreshToken: String) async -> AuthSession? {
        if let existing = refreshTask { return await existing.value }

        let task = Task { () -> AuthSession? in
            try? await authService.refresh(refreshToken: refreshToken)
        }
        refreshTask = task
        let refreshed = await task.value
        refreshTask = nil

        if let refreshed {
            try? keychain.save(refreshed)
            state = .signedIn(refreshed)
        } else {
            keychain.clear()
            state = .signedOut
        }
        return refreshed
    }

    private func authenticate(_ action: () async throws -> AuthSession) async {
        isWorking = true
        errorMessage = nil
        do {
            let session = try await action()
            try keychain.save(session)
            state = .signedIn(session)
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
