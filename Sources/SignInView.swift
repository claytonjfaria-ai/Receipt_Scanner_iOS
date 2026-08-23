import Darwin
import SwiftUI

/// Plan §8: "Sign in with your tap2know account — the same email and password you already
/// use on the web." Redesigned 2026-08-23 from Clayton's own mockup — a branded card over a
/// teal gradient, replacing the original plain-`Form` look. Deliberately not dark-mode-aware:
/// a login/welcome screen with a fixed brand background regardless of system appearance is
/// common precedent (Notion, Copilot Money, and most of the apps pulled as references all do
/// the same), and matches the mockup exactly rather than approximating it twice.
struct SignInView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private var canSignIn: Bool { !isSigningIn && !email.isEmpty && !password.isEmpty && Secrets.isConfigured }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background

                ScrollView {
                    VStack(spacing: 20) {
                        card
                        // Small and secondary on purpose, not folded into the card itself:
                        // this is diagnostic info (bundle ID + build, for registering Google's
                        // OAuth client and confirming which .ipa is installed), not part of the
                        // sign-in flow a real user cares about. Still visible on this screen
                        // without signing in first -- see this section's own history below.
                        diagnostics
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 40)
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .alert("Couldn't sign in", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.billScannerTealLight, .billScannerTealDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.billScannerTeal)

            VStack(spacing: 6) {
                Text("Welcome to Bill Scanner")
                    .font(.title2.bold())
                    .foregroundStyle(Color.billScannerNavy)
                    .multilineTextAlignment(.center)
                Text("Sign in to scan, track and manage your bills")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Unchanged from before the redesign, just restyled to fit: a build with no
            // Supabase secrets configured can never get past this screen, so this has to stay
            // visible here, not gated behind sign-in succeeding.
            if !Secrets.isConfigured {
                Text("Not configured: SUPABASE_URL/SUPABASE_ANON_KEY were never set for this build. See secrets.env.example.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                labeledField("EMAIL") {
                    TextField("yourname@email.com", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                labeledField("PASSWORD") {
                    SecureField("••••••••••", text: $password)
                        .textContentType(.password)
                }
            }

            HStack(spacing: 12) {
                Button(action: signIn) {
                    Group {
                        if isSigningIn {
                            ProgressView().tint(.white)
                        } else {
                            Text("Sign In").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 14)
                .background(canSignIn ? Color.billScannerTeal : Color.billScannerTeal.opacity(0.5))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(!canSignIn)

                // `exit(0)` -- see `quitApp`'s own kdoc for why an abrupt process kill is the
                // actual, deliberate answer here, not a placeholder.
                Button(action: quitApp) {
                    Text("Cancel").fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 14)
                .foregroundStyle(Color.billScannerNavy)
                .background(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.billScannerTeal.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Deliberately not wired up yet -- Clayton's own call 2026-08-23: both household
            // sign-ins already know their passwords, so a real reset flow isn't worth building
            // until that stops being true. Left tappable-looking (matching the mockup) rather
            // than visually disabled, so it doesn't read as broken -- it's just not built yet.
            Button("Forgot your password?") {}
                .font(.footnote)
                .foregroundStyle(Color.billScannerTeal)
        }
        .padding(28)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.billScannerTeal)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4)))
        }
    }

    // MARK: - Diagnostics

    /// Deliberately on THIS screen, not only inside `CaptureView`'s own Diagnostics section —
    /// reading the real bundle ID (plan §4.4's OAuth-client prerequisite) has nothing to do
    /// with being signed in. Found live on-device 2026-08-23: gating this behind sign-in was a
    /// mistake, since a build with broken secrets can never reach the other screen. Wrapped in
    /// its own solid card, not placed directly on the teal background: `CopyableRow` uses
    /// `.secondary`/default-`.primary` text colors meant for a light background, and this
    /// redesign shouldn't have to fork that shared component just to sit on a colored one.
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 6) {
            CopyableRow(label: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "unknown")
            CopyableRow(label: "Version", value: "\(shortVersion) (\(buildNumber))")
        }
        .padding(14)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    // MARK: - Actions

    private func signIn() {
        isSigningIn = true
        Task {
            do {
                try await auth.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }

    /// Clayton's own explicit choice (2026-08-23): "Cancel should close the app and return the
    /// user to the Home Screen." `exit(0)` is the real, if blunt, way to do that on iOS — an
    /// instant kill with no dismissal animation, indistinguishable on-screen from a crash. Apple's
    /// App Store guidelines steer consumer apps away from a self-quitting button for exactly that
    /// reason; that guidance doesn't bind this app, since it's sideloaded via SideStore and never
    /// submitted for review (plan §8's whole install pipeline). Not used as an error-recovery
    /// mechanism anywhere else in the app — this is the one deliberate, requested exception.
    private func quitApp() {
        exit(0)
    }
}

// MARK: - Palette

/// Internal, not `private` — deliberately reusable if more screens get this same redesign
/// treatment later, without needing to promote these to a shared theme file first for a
/// one-screen change. Approximate to Clayton's mockup, not a pixel-sampled match.
extension Color {
    static let billScannerTealLight = Color(red: 0.24, green: 0.78, blue: 0.76)
    static let billScannerTealDark = Color(red: 0.04, green: 0.37, blue: 0.38)
    static let billScannerTeal = Color(red: 0.05, green: 0.49, blue: 0.49)
    static let billScannerNavy = Color(red: 0.10, green: 0.19, blue: 0.26)
}
