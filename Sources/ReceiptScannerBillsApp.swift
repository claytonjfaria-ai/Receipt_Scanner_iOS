import SwiftUI

/// The real Bills-capture iOS app (plan §8 of PLAN-MOBILE-BILLS-CAPTURE.md), not the
/// BillsCaptureTest pipeline proof (dev/iOs_Test). Full parity with Android's Bills tab is
/// the eventual goal — capture, extract-bill, review, redact, file to Drive — built up in
/// the same dependency order the plan used on Android (§4.1 first).
///
/// Milestone 2 (current): capture + review + `extract-bill`. Sign-in is new at this
/// milestone too — extract-bill's `verify_jwt` gate needs a real Supabase session (plan §8:
/// "unrelated to tap2know web's household-ledger multi-account reasoning... the JWT's only
/// job here is proving an allowed household member is asking"). No Drive OAuth, no real
/// filing yet.
@main
struct ReceiptScannerBillsApp: App {
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
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
