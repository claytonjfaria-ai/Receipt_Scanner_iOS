import Foundation

/// Owns the Drive OAuth session: persists it to the Keychain (its own account key, separate from
/// the Supabase session — see `DriveSession`'s header), restores on launch, refreshes on demand.
/// Mirrors `AuthStore`'s shape deliberately, since the two solve the same problem for two
/// unrelated identity systems.
@MainActor
final class DriveAuthStore: ObservableObject {
    @Published private(set) var session: DriveSession?

    private let keychainAccount = "drive_session"
    private let oauthClient = GoogleOAuthClient()

    init() {
        restore()
    }

    var isConnected: Bool { session != nil }

    func signIn() async throws {
        let session = try await oauthClient.signIn()
        persist(session)
    }

    func disconnect() {
        session = nil
        KeychainStore.delete(account: keychainAccount)
    }

    /// A token safe to use right now — refreshes first if the current one is expired or about to
    /// be. Throws rather than returning a stale token, same reasoning as `AuthStore`'s equivalent.
    func validAccessToken() async throws -> String {
        guard let current = session else { throw GoogleOAuthError.notSignedIn }
        guard current.isExpiredOrExpiringSoon else { return current.accessToken }

        let refreshed = try await oauthClient.refresh(refreshToken: current.refreshToken)
        persist(refreshed)
        return refreshed.accessToken
    }

    private func restore() {
        guard
            let data = KeychainStore.load(account: keychainAccount),
            let restored = try? JSONDecoder().decode(DriveSession.self, from: data)
        else { return }
        session = restored
    }

    private func persist(_ session: DriveSession) {
        self.session = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        KeychainStore.save(data, account: keychainAccount)
    }
}
