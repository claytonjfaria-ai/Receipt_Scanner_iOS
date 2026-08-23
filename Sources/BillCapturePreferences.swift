import Foundation

/// Sticky archive-resolution setting — plan §4.1: "The user picks the resolution; the app
/// remembers it... set once, not asked per scan." Android's precedent is
/// `ScanTutorialPreferences.kt`, a thin `SharedPreferences` wrapper; the plan names
/// `@AppStorage` as the iOS equivalent directly.
///
/// Lives on the capture screen itself (§4.1: "not a Settings screen" — iOS has no settings
/// surface yet either, same reasoning as Android).
enum BillCapturePreferences {
    private static let dpiKey = "bill_capture_dpi"

    static var resolution: CompressionProfile {
        get {
            let stored = UserDefaults.standard.integer(forKey: dpiKey)
            return CompressionProfile(rawValue: stored) ?? .default
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dpiKey) }
    }
}
