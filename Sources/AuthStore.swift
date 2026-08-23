import Foundation

/// Owns the signed-in session: restores it from the Keychain on launch, refreshes it when
/// needed, and is what `ExtractBillClient` asks for a valid access token.
///
/// Plan §8: this sign-in has nothing to do with tap2know web's household-ledger multi-account
/// model — it exists solely to obtain a JWT that satisfies `extract-bill`'s `verify_jwt` gate.
/// Any allowlisted household email works; nothing here distinguishes accounts.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var isRestoring = true

    private let keychainAccount = "session"

    init() {
        restore()
    }

    var isSignedIn: Bool { session != nil }

    func signIn(email: String, password: String) async throws {
        let session = try await SupabaseAuthClient.signIn(email: email, password: password)
        persist(session)
    }

    func signOut() {
        session = nil
        KeychainStore.delete(account: keychainAccount)
    }

    /// A token safe to use right now — refreshes first if the current one is expired or about
    /// to be. Throws (rather than silently returning a stale token) so callers can route the
    /// user back to sign-in on a hard failure, e.g. a refresh token that's itself expired.
    func validAccessToken() async throws -> String {
        guard let current = session else { throw SupabaseAuthError.notSignedIn }

        guard current.isExpiredOrExpiringSoon else { return current.accessToken }

        let refreshed = try await SupabaseAuthClient.refresh(refreshToken: current.refreshToken)
        persist(refreshed)
        return refreshed.accessToken
    }

    private func restore() {
        defer { isRestoring = false }
        guard
            let data = KeychainStore.load(account: keychainAccount),
            let restored = try? JSONDecoder().decode(AuthSession.self, from: data)
        else { return }
        session = restored
    }

    private func persist(_ session: AuthSession) {
        self.session = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        KeychainStore.save(data, account: keychainAccount)
    }
}
