import CryptoKit
import Foundation

/// RFC 7636 PKCE (Proof Key for Code Exchange) — required by Google's native-app OAuth flow so
/// the authorization code, intercepted by anything watching the system browser, can't be
/// redeemed by anyone but this app (only this run holds `verifier`, never sent except in the
/// final token-exchange request over HTTPS).
enum PKCE {
    struct Pair {
        let verifier: String
        let challenge: String
    }

    static func generate() -> Pair {
        let verifier = randomVerifier()
        return Pair(verifier: verifier, challenge: codeChallenge(for: verifier))
    }

    /// 43–128 characters from the unreserved set `[A-Za-z0-9-._~]`, per RFC 7636 §4.1.
    private static func randomVerifier(length: Int = 64) -> String {
        let allowed = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).compactMap { _ in allowed.randomElement() })
    }

    /// S256: Base64URL (no padding) of the SHA-256 hash of the verifier.
    private static func codeChallenge(for verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return Data(hashed).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
