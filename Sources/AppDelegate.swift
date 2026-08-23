import UIKit

/// The one piece of this SwiftUI app that still needs a real `UIApplicationDelegate` —
/// orientation restriction has no SwiftUI-native equivalent. `project.yml`'s
/// `UISupportedInterfaceOrientations` sets the ceiling (portrait + all landscape, on both iPhone
/// and iPad); this narrows it at runtime based on `OrientationPreferences.allowLandscape`, which
/// can only ever restrict *within* that ceiling, never widen past it.
///
/// Governs every screen in the app, including the scanner: `VNDocumentCameraViewController` is
/// presented in the same window scene via `.fullScreenCover` (`DocumentScanner.swift`), so it
/// inherits this restriction the same way any other presented view controller would — not
/// verified on-device as of this commit, since system camera-adjacent pickers have occasionally
/// had their own orientation quirks historically; worth confirming for real once installed.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationPreferences.allowLandscape ? .all : .portrait
    }
}
