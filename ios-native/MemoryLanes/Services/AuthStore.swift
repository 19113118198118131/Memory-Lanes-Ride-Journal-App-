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

    init() {
        if let session = keychain.load(), !session.isExpired {
            state = .signedIn(session)
        } else {
            keychain.clear()
            state = .signedOut
        }
    }

    var accessToken: String? {
        if case .signedIn(let session) = state { return session.accessToken }
        return nil
    }

    var email: String? {
        if case .signedIn(let session) = state { return session.email }
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
        keychain.clear()
        state = .signedOut
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
