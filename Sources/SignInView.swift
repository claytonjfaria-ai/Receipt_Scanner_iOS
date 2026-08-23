import SwiftUI

/// Plan §8: "Sign in with your tap2know account — the same email and password you already
/// use on the web." Same copy convention the Android app's sign-in screen uses (main plan,
/// First-run sign-in hint) — no mention of which two emails are allowlisted, matching the
/// backend's own deliberately generic failure message.
struct SignInView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if !Secrets.isConfigured {
                    Section {
                        Text("Not configured: SUPABASE_URL/SUPABASE_ANON_KEY were never set for this build. See secrets.env.example.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Sign in with your tap2know account — the same email and password you already use on the web.")
                }

                Section {
                    Button {
                        signIn()
                    } label: {
                        if isSigningIn {
                            ProgressView()
                        } else {
                            Text("Sign in")
                        }
                    }
                    .disabled(isSigningIn || email.isEmpty || password.isEmpty || !Secrets.isConfigured)
                }

                // Deliberately on THIS screen, not only inside CaptureView's own Diagnostics
                // section — reading the real bundle ID (plan §4.4's OAuth-client prerequisite)
                // has nothing to do with being signed in, and a build with no Supabase secrets
                // configured can never get past this screen to reach the other one. Found live
                // on-device 2026-08-23: the diagnostics-only-after-sign-in design was a mistake.
                Section("Diagnostics") {
                    CopyableRow(label: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "unknown")
                }
            }
            .navigationTitle("Bills")
            .alert("Couldn't sign in", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

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
}
