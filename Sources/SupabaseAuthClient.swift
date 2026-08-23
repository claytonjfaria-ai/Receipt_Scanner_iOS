import Foundation

enum SupabaseAuthError: LocalizedError {
    case notConfigured
    case notSignedIn
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase isn't configured on this build — SUPABASE_URL/SUPABASE_ANON_KEY were never set. See secrets.env.example."
        case .notSignedIn:
            return "Sign in to continue."
        case .invalidResponse:
            return "Unexpected response from the sign-in server."
        case .server(let message):
            return message
        }
    }
}

/// Talks to Supabase's GoTrue REST API directly — no `supabase-swift` SDK dependency.
///
/// Deliberate, not an oversight: this app needs exactly two calls (sign in, refresh), and
/// pulling in the official SDK means SPM package resolution inside the unsigned-CI-build
/// pipeline (network access, version pinning, a dependency the build has never needed before).
/// Same reasoning the main plan gives for the Android app's supabase-kt fallback — "the
/// fallback is Postgrest/Storage REST ... directly" — applied here from the start rather than
/// as a fallback, since the surface area needed is this small.
enum SupabaseAuthClient {
    static func signIn(email: String, password: String) async throws -> AuthSession {
        try await tokenRequest(query: "grant_type=password", body: [
            "email": email,
            "password": password,
        ])
    }

    static func refresh(refreshToken: String) async throws -> AuthSession {
        try await tokenRequest(query: "grant_type=refresh_token", body: [
            "refresh_token": refreshToken,
        ])
    }

    private static func tokenRequest(query: String, body: [String: String]) async throws -> AuthSession {
        guard
            let baseURL = Secrets.supabaseURL,
            let anonKey = Secrets.supabaseAnonKey
        else { throw SupabaseAuthError.notConfigured }

        var components = URLComponents(url: baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.query = query
        guard let url = components?.url else { throw SupabaseAuthError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data))?.message
            throw SupabaseAuthError.server(message ?? "Sign-in failed (\(http.statusCode))")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(SupabaseTokenResponse.self, from: data).session
    }
}
