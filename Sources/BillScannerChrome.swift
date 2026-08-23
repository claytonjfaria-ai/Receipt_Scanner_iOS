import SwiftUI

/// Shared visual shell for the app's primary screens (Sign In, Bills home, Review) — the teal
/// gradient + decorative circles background, factored out once it showed up on a third screen
/// (Review) rather than copied a third time. `SignInView` originally defined this inline; still
/// owns the `Color.billScanner*` palette it and this file both use.
struct BillScannerBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.billScannerTealLight, .billScannerTealDark], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 280, height: 280)
                .offset(x: -150, y: -320)
            Circle()
                .fill(Color.black.opacity(0.12))
                .frame(width: 240, height: 240)
                .offset(x: 160, y: 340)
        }
        .ignoresSafeArea()
    }
}

/// The persistent "Bill Scanner" + settings-gear header shared by the Bills home screen and
/// Review — both of Clayton's mockups (2026-08-23) show the identical header, meaning Review
/// isn't a separate pushed screen with its own nav bar/back button. Confirmed explicitly rather
/// than assumed: Save/Redact/Discard are the only way out of Review now, matching the mockup —
/// see `BillReviewView`'s own header comment for the full reasoning. Drive connection, the Scans
/// folder, resolution, and Sign out all moved behind this gear icon into `SettingsView`, also
/// Clayton's own explicit call, not a guess — none of that appeared in either mockup either.
struct BillScannerHeader: View {
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bill Scanner")
                    .font(.title2.bold())
                    .foregroundStyle(Color.billScannerNavy)
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .foregroundStyle(Color.billScannerNavy)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            Divider()
        }
    }
}

/// The rounded white card every primary screen's header + content sits inside.
struct BillScannerCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
    }
}

/// One of the three pill-shaped action buttons on Review (Save / Redact / Discard), and reused
/// by the Bills home screen's own action styling where the same shape applies.
struct BillScannerPillButton: View {
    enum Style { case filled, outlined }

    let title: String
    let style: Style
    var tint: Color = .billScannerTeal
    var isDisabled = false
    /// Swaps the title for a spinner and forces `isDisabled` — a network action in flight
    /// (Sign In, Save) needs visible feedback for however long it takes, not just a disabled
    /// button that looks identical to "not allowed yet."
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(style == .filled ? .white : tint)
                } else {
                    Text(title).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .background(style == .filled ? (isDisabled ? tint.opacity(0.5) : tint) : Color.white)
        .foregroundStyle(style == .filled ? .white : tint)
        .overlay {
            if style == .outlined {
                RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(isDisabled || isLoading)
    }
}
