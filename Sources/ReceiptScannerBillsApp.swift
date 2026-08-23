import SwiftUI

/// The real Bills-capture iOS app (plan §8 of PLAN-MOBILE-BILLS-CAPTURE.md), not the
/// BillsCaptureTest pipeline proof (dev/iOs_Test). Full parity with Android's Bills tab is
/// the eventual goal — capture, extract-bill, review, redact, file to Drive — built up in
/// the same dependency order the plan used on Android (§4.1 first).
///
/// Milestone 1 (current): capture only — VisionKit → an on-device multi-page PDF, matching
/// §4.1's compression target. No extract-bill call, no Drive OAuth, no filing yet.
@main
struct ReceiptScannerBillsApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
        }
    }
}
