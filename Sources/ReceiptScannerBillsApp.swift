import SwiftUI

/// The real Bills-capture iOS app (plan §8 of PLAN-MOBILE-BILLS-CAPTURE.md), not the
/// BillsCaptureTest pipeline proof (dev/iOs_Test). Full parity with Android's Bills tab is
/// the eventual goal — capture, extract-bill, review, redact, file to Drive — built up in
/// the same dependency order the plan used on Android (§4.1 first).
///
/// Milestone 3 (current): Drive OAuth sign-in, the Scans folder picker, and real filing
/// (`BillFilingService`) are all wired up now. `DriveAuthStore` is a second, independent identity
/// system from `AuthStore` (Supabase) — see `DriveSession.swift`'s header for why they're
/// deliberately not unified.
@main
struct ReceiptScannerBillsApp: App {
    // Orientation restriction (2026-08-23, Settings' "Allow landscape" toggle) has no
    // SwiftUI-native equivalent -- see AppDelegate.swift's own kdoc.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthStore()
    @StateObject private var driveAuth = DriveAuthStore()
    @StateObject private var folderPreferences = DriveFolderPreferences()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(driveAuth)
                .environmentObject(folderPreferences)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        Group {
            if auth.isRestoring {
                ProgressView()
            } else if auth.isSignedIn {
                CaptureView()
            } else {
                SignInView()
            }
        }
    }
}
