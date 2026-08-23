import Foundation

/// Google Cloud Console project "Receipt Scanner Bills" — the same project Android's Bills work
/// already uses (plan §4.4). This client was created 2026-08-23, bound to the confirmed,
/// sideloading-rewritten bundle ID `com.tap2know.receiptscanner.bills.7HKHVWJDHC`.
enum GoogleOAuthConfig {
    /// Not a secret, unlike SUPABASE_ANON_KEY's gitignored treatment — native-app OAuth client
    /// IDs are meant to ship inside the binary; anyone who decompiles the app already sees this.
    /// Google's security model for this flow rests on PKCE (the code_verifier never leaves the
    /// device) and the client's bundle-ID binding, not on this string staying hidden. Hardcoded
    /// plainly rather than routed through Secrets.swift's env-var mechanism for that reason —
    /// there's also no dev/prod split for it the way there is for Supabase's URL/anon key.
    static let clientID = "138014836118-cce333u1f9plimlr604141m9pbtvq6p0.apps.googleusercontent.com"

    /// Google's documented convention for native iOS apps without a client secret: the reversed
    /// client ID as a custom URL scheme. Must exactly match the `CFBundleURLSchemes` entry in
    /// project.yml, and must match `callbackURLScheme` passed to `ASWebAuthenticationSession`.
    static let redirectURIScheme = "com.googleusercontent.apps.138014836118-cce333u1f9plimlr604141m9pbtvq6p0"
    static let redirectURI = "\(redirectURIScheme):/oauth2redirect"

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// Full `drive` scope, not `drive.file` — plan §4.4's scope reversal (2026-08-22), confirmed
    /// necessary on Android: `drive.file` cannot see a picked folder's *pre-existing* contents,
    /// only what the app itself creates afterward. Same mechanism, same reasoning, on iOS.
    static let scope = "https://www.googleapis.com/auth/drive"
}
