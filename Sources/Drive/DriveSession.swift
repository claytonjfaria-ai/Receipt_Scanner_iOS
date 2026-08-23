import Foundation

/// A Google Drive OAuth session — deliberately its own type, not reusing `AuthSession`
/// (Supabase's), even though the shape is identical. These are two unrelated identity systems
/// (plan §8: the Supabase sign-in exists only to satisfy `extract-bill`'s JWT gate; this one is
/// real Google Drive access) that happen to need the same access/refresh/expiry fields — sharing
/// a type here would couple them for no real benefit and make a future divergence (e.g. Drive
/// needing to track granted scopes) awkward to add without touching Supabase's model too.
struct DriveSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpiredOrExpiringSoon: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }
}
