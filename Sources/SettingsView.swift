import SwiftUI
import UIKit

/// Everything that used to sit directly on the Bills home screen, moved behind that screen's
/// gear icon once Clayton's redesign (2026-08-23) needed the main screen to stay as clean as
/// his mockup — Drive connection, the Scans folder picker, archive resolution, and Sign out.
/// Clayton's own explicit call, not a guess: neither of his two mockups showed any of this, and
/// "behind the gear icon" was the settled answer when asked where it should go.
///
/// Plain system `List` styling deliberately, not yet given the same card/teal treatment as the
/// rest of the app — that wasn't part of what was redesigned this round, and a functional-parity
/// move first, restyled later if wanted, is safer than guessing at a visual language for a screen
/// nobody has actually mocked up.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var driveAuth: DriveAuthStore
    @EnvironmentObject private var folderPreferences: DriveFolderPreferences

    @Environment(\.dismiss) private var dismiss

    @State private var resolution = BillCapturePreferences.resolution
    @State private var allowLandscape = OrientationPreferences.allowLandscape
    @State private var isDriveConnecting = false
    @State private var isFolderPickerPresented = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                driveSection
                resolutionSection
                orientationSection
                Section {
                    Button("Sign out", role: .destructive) { auth.signOut() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isFolderPickerPresented) {
                FolderPickerView { isFolderPickerPresented = false }
            }
            .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var driveSection: some View {
        Section {
            if driveAuth.isConnected {
                Label("Connected to Google Drive", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let folder = folderPreferences.scansFolder {
                    HStack {
                        Text("Scans folder")
                        Spacer()
                        Text(folder.name).foregroundStyle(.secondary)
                    }
                    Button("Change folder") { isFolderPickerPresented = true }
                } else {
                    Button("Choose Scans folder") { isFolderPickerPresented = true }
                }
                Button("Disconnect", role: .destructive) { driveAuth.disconnect() }
            } else {
                Button {
                    connectDrive()
                } label: {
                    if isDriveConnecting {
                        ProgressView()
                    } else {
                        Text("Connect Google Drive")
                    }
                }
                .disabled(isDriveConnecting)
            }
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        if !driveAuth.isConnected { return "Connect Google Drive, then choose your Scans folder, to file bills automatically." }
        if folderPreferences.scansFolder == nil { return "Choose your Scans folder to start filing bills automatically." }
        return "New bills file straight to this folder on Save."
    }

    private var resolutionSection: some View {
        Section {
            Picker("Archive resolution", selection: $resolution) {
                ForEach(CompressionProfile.allCases) { profile in
                    Text(profile.label).tag(profile)
                }
            }
            // Single-parameter form deliberately — the two-parameter (`oldValue, newValue`)
            // overload needs iOS 17, and this target's deploymentTarget is 16.0.
            .onChange(of: resolution) { newValue in
                BillCapturePreferences.resolution = newValue
            }
        } footer: {
            Text("Applies to new scans. Higher resolution keeps small print (account numbers, dates) sharper but makes a larger file.")
        }
    }

    /// 2026-08-23, Clayton's explicit ask: the app defaults to portrait everywhere, including
    /// while scanning, with this as the one opt-in escape hatch. Off is a hard portrait lock, not
    /// just a preference the OS might still ignore — see `AppDelegate.swift`. On allows rotating
    /// into landscape; it does not *force* landscape (his own explicit choice when asked).
    private var orientationSection: some View {
        Section {
            Toggle("Allow landscape", isOn: $allowLandscape)
                .onChange(of: allowLandscape) { newValue in
                    OrientationPreferences.allowLandscape = newValue
                    applyOrientationChange(allowLandscape: newValue)
                }
        } footer: {
            Text("Off keeps the app in portrait everywhere, including while scanning. On lets it rotate into landscape too.")
        }
    }

    // MARK: - Actions

    private func connectDrive() {
        isDriveConnecting = true
        Task {
            do {
                try await driveAuth.signIn()
            } catch {
                errorMessage = error.localizedDescription
            }
            isDriveConnecting = false
        }
    }

    /// `AppDelegate`'s `supportedInterfaceOrientationsFor:` alone only takes effect on the
    /// *next* orientation-negotiation event (e.g. an actual device rotation) -- without this,
    /// toggling the setting would silently do nothing until the user happened to rotate the
    /// device anyway. `requestGeometryUpdate` (iOS 16+, matching this target's deployment
    /// target) forces the window scene to re-query and apply the new mask immediately.
    private func applyOrientationChange(allowLandscape: Bool) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        let mask: UIInterfaceOrientationMask = allowLandscape ? .all : .portrait
        // Best-effort, no completion handler needed: worst case the new mask still applies on
        // the next natural rotation event, same as if this call hadn't been made at all.
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}
