import Foundation

actor AccountDeletionService {
    private let client: SupabaseHTTPClient

    init(client: SupabaseHTTPClient = SupabaseHTTPClient()) {
        self.client = client
    }

    func requestDeletion(accessToken: String) async throws {
        let accepted: Bool = try await client.post(
            path: "rest/v1/rpc/request_account_deletion",
            body: AccountDeletionPayload(),
            accessToken: accessToken
        )
        guard accepted else { throw AccountDeletionError.notAccepted }
    }
}

enum AccountDeletionError: LocalizedError {
    case notAccepted

    var errorDescription: String? {
        switch self {
        case .notAccepted:
            "We could not start your deletion request. Please try again."
        }
    }
}

private struct AccountDeletionPayload: Encodable {}
