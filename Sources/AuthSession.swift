import Foundation

/// A signed-in session — just enough to satisfy `extract-bill`'s JWT gate (plan §8: "the JWT's
/// only job here is proving an allowed household member is asking," nothing account-specific).
struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    /// A minute of slack so a token that's about to expire isn't used for a request that then
    /// takes a few seconds to reach the server.
    var isExpiredOrExpiringSoon: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }
}

/// Raw shape of Supabase GoTrue's token endpoint response (both `grant_type=password` and
/// `grant_type=refresh_token` return the same shape). Decoded separately from `AuthSession`
/// because the wire format is snake_case and gives `expires_in` (a duration), not the
/// `expiresAt` timestamp `AuthSession` actually wants to store.
struct SupabaseTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    var session: AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }
}

struct SupabaseErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?
    let msg: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case msg
    }

    /// GoTrue has used different error shapes across versions (`error_description`, `msg`,
    /// bare `error`) — surface whichever is present rather than a blank message.
    var message: String {
        errorDescription ?? msg ?? error ?? "Sign-in failed"
    }
}
