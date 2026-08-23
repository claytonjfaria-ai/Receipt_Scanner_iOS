import Foundation

/// Sticky orientation-lock setting, same `UserDefaults`-backed shape as `BillCapturePreferences`.
/// Off (the default) means portrait-only everywhere, including while scanning — Clayton's
/// explicit ask (2026-08-23): `project.yml`'s `UISupportedInterfaceOrientations` had always
/// statically allowed landscape too, with nothing actually restricting it at runtime, so the app
/// (and the scanner inside it) rotated freely. On allows the device to rotate between portrait
/// and landscape — his own explicit choice when asked: a landscape *option*, not a landscape
/// *lock*.
enum OrientationPreferences {
    private static let allowLandscapeKey = "allow_landscape"

    static var allowLandscape: Bool {
        get { UserDefaults.standard.bool(forKey: allowLandscapeKey) }
        set { UserDefaults.standard.set(newValue, forKey: allowLandscapeKey) }
    }
}
