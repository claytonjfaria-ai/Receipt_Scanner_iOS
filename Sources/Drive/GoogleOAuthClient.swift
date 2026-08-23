import AuthenticationServices
import UIKit

enum GoogleOAuthError: LocalizedError {
    case notSignedIn
    case cancelled
    case invalidCallback
    case missingCode
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Connect Google Drive to continue."
        case .cancelled: return "Google sign-in was cancelled."
        case .invalidCallback: return "Unexpected callback from Google sign-in."
        case .missingCode: return "Google sign-in did not return an authorization code."
        case .invalidResponse: return "Unexpected response from Google."
        case .server(let message): return message
        }
    }
}

/// Google's native-app OAuth 2.0 flow: authorization-code + PKCE via `ASWebAuthenticationSession`
/// (a system browser sheet, not an in-app `WKWebView` — Android's own §4.4 build hit a real
/// `postMessage`-origin bug from embedding Google's picker.js in a WebView; using the system
/// browser session here sidesteps that whole class of problem, and it's also what lets Drive
/// sign-in share cookies/session state with Safari if the user's already signed into Google
/// there). Verified against Google's own current docs before writing this, not from memory —
/// specifically: iOS installed apps always get a refresh token back (no `access_type=offline`
/// needed, unlike a web server flow), and the redirect URI is the reversed-client-ID custom
/// scheme, matched via `callbackURLScheme` rather than a Console-registered redirect URI list
/// (the iOS OAuth client type has no such field, unlike Web clients).
@MainActor
final class GoogleOAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func signIn() async throws -> DriveSession {
        let pkce = PKCE.generate()
        let state = UUID().uuidString

        guard var components = URLComponents(url: GoogleOAuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw GoogleOAuthError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authURL = components.url else { throw GoogleOAuthError.invalidResponse }

        let callbackURL = try await authenticate(url: authURL)

        guard
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
            returnedState == state
        else { throw GoogleOAuthError.invalidCallback }

        guard let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            if let serverError = callbackComponents.queryItems?.first(where: { $0.name == "error" })?.value {
                throw GoogleOAuthError.server(serverError)
            }
            throw GoogleOAuthError.missingCode
        }

        return try await tokenRequest(
            body: [
                "client_id": GoogleOAuthConfig.clientID,
                "code": code,
                "code_verifier": pkce.verifier,
                "grant_type": "authorization_code",
                "redirect_uri": GoogleOAuthConfig.redirectURI,
            ],
            fallbackRefreshToken: nil
        )
    }

    func refresh(refreshToken: String) async throws -> DriveSession {
        try await tokenRequest(
            body: [
                "client_id": GoogleOAuthConfig.clientID,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token",
            ],
            fallbackRefreshToken: refreshToken
        )
    }

    // MARK: - System browser session

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleOAuthConfig.redirectURIScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleOAuthError.cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleOAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            // Not ephemeral: lets sign-in reuse an existing Google session/cookie in the system
            // browser rather than forcing a full email+password entry every time.
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session

            // start() returning false (e.g. another session already active) means the
            // completion handler above never fires — without this check, that would hang the
            // continuation forever instead of throwing. The two paths are mutually exclusive:
            // a false return is documented to mean the handler is never called, so this can't
            // race a legitimate completion and double-resume.
            if !session.start() {
                continuation.resume(throwing: GoogleOAuthError.invalidCallback)
            }
        }
    }

    // MARK: - Token endpoint

    private func tokenRequest(body: [String: String], fallbackRefreshToken: String?) async throws -> DriveSession {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedBody(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleOAuthError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(GoogleOAuthErrorResponse.self, from: data))?.errorDescription
            throw GoogleOAuthError.server(message ?? "Token request failed (\(http.statusCode))")
        }

        let decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        // A refresh grant doesn't always return a new refresh_token -- Google may omit it,
        // meaning the one that was just used is still valid. Fall back to that rather than
        // treating a missing field here as an error.
        guard let refreshToken = decoded.refreshToken ?? fallbackRefreshToken else {
            throw GoogleOAuthError.invalidResponse
        }

        return DriveSession(
            accessToken: decoded.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(decoded.expiresIn)
        )
    }

    /// Minimal, explicit unreserved-character allowlist (RFC 3986 §2.3) rather than
    /// `CharacterSet.urlQueryAllowed` — that system set's exact excluded characters aren't
    /// something to trust from memory for a form body (as opposed to a URL's query component,
    /// which is a different, if similar, context); encoding everything outside this minimal safe
    /// set is always correct, even where it's not strictly required.
    private func formURLEncodedBody(_ parameters: [String: String]) -> Data? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let pairs = parameters.map { key, value -> String in
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encodedValue)"
        }
        return pairs.joined(separator: "&").data(using: .utf8)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    /// Found live on-device 2026-08-23: this used to be an unconditional
    /// `DispatchQueue.main.sync { ... }`, on the theory that the framework doesn't guarantee
    /// which thread calls this. That was wrong in the way that matters most — in practice,
    /// `session.start()` calls this synchronously **on the main thread**, and since this whole
    /// class is `@MainActor` (so `signIn()` → `authenticate(url:)` → `session.start()` all run
    /// on the main thread already), an unconditional `.sync` targeting the main queue **from**
    /// the main queue is a classic self-deadlock — the app hangs, and iOS's watchdog kills it,
    /// which looks exactly like "the app closes to the Home Screen" with no error ever shown.
    /// Checking `Thread.isMainThread` first avoids the deadlock while still being safe if some
    /// future iOS version ever does call this off the main thread.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if Thread.isMainThread {
            return Self.keyWindow() ?? ASPresentationAnchor()
        }
        return DispatchQueue.main.sync { Self.keyWindow() ?? ASPresentationAnchor() }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

private struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct GoogleOAuthErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
