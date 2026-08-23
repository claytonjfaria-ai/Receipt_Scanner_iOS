import SwiftUI

/// Milestone 3 of the real iOS Bills app: capture → assemble a durable on-device PDF →
/// review + `extract-bill` → connect Google Drive → pick a Scans folder → Review's Save files
/// for real (`BillFilingService`). Falls back to the pre-Drive local sidecar (`BillMetadataStore`)
/// only when Drive isn't connected or no folder has been chosen yet.
struct CaptureView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var driveAuth: DriveAuthStore
    @EnvironmentObject private var folderPreferences: DriveFolderPreferences

    @State private var pages: [UIImage] = []
    @State private var isScannerPresented = false
    @State private var errorMessage: String?
    @State private var resolution = BillCapturePreferences.resolution
    @State private var stagedPDFs: [URL] = BillPdfStore.stagedPDFs()
    @State private var isSaving = false
    @State private var pendingReview: PendingBill?
    @State private var isDriveConnecting = false
    @State private var isFolderPickerPresented = false

    var body: some View {
        NavigationStack {
            List {
                if !pages.isEmpty {
                    capturedSection
                }
                driveSection
                resolutionSection
                if !stagedPDFs.isEmpty {
                    stagedSection
                }
                diagnosticsSection
            }
            .navigationTitle("Bills")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Sign out", role: .destructive) { auth.signOut() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isScannerPresented = true
                    } label: {
                        Label("Scan", systemImage: "doc.viewfinder")
                    }
                }
            }
            .overlay {
                if pages.isEmpty && stagedPDFs.isEmpty {
                    emptyState
                }
            }
            .fullScreenCover(isPresented: $isScannerPresented) {
                DocumentScanner(
                    onFinish: { captured in
                        pages = captured
                        isScannerPresented = false
                    },
                    onCancel: { isScannerPresented = false },
                    onError: { error in
                        errorMessage = error.localizedDescription
                        isScannerPresented = false
                    }
                )
                .ignoresSafeArea()
                // Safety net, not a duplicate: on a real device (2026-08-23, Clayton's iPad)
                // VNDocumentCameraViewController's own top toolbar -- where its built-in Cancel
                // and flash controls normally live -- didn't render at all, most likely because
                // `.ignoresSafeArea()` above interferes with how that system view controller lays
                // out controls anchored to the safe area. Rather than chase VisionKit's internal
                // layout, this button is placed and hardcoded-padded independent of it, so an exit
                // exists regardless of whether that root cause is right.
                .overlay(alignment: .topLeading) {
                    Button("Cancel") {
                        isScannerPresented = false
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.top, 50)
                    .padding(.leading, 16)
                }
            }
            // navigationDestination(item:) needs iOS 17; this target is 16.0 (matching
            // BillsCaptureTest, deliberately, for the same device-compatibility reasons).
            // isPresented: form is the iOS-16-compatible equivalent — caught by CI, not
            // locally, same as the last two issues.
            .navigationDestination(isPresented: isReviewPresented) {
                if let pendingReview {
                    BillReviewView(pending: pendingReview) {
                        self.pendingReview = nil
                        stagedPDFs = BillPdfStore.stagedPDFs()
                    }
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

    /// Derived, not `@State` — `pendingReview` itself stays the single source of truth
    /// (needed for its actual data, not just presence); this is only what
    /// `navigationDestination(isPresented:)` needs to know whether to show it.
    private var isReviewPresented: Binding<Bool> {
        Binding(
            get: { pendingReview != nil },
            set: { isPresented in
                if !isPresented { pendingReview = nil }
            }
        )
    }

    // MARK: - Sections

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Scan a bill")
                    .font(.headline)
                Text("Point the camera at each page. It captures automatically once the page is flat and in frame.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Button("Scan pages") { isScannerPresented = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var capturedSection: some View {
        Section("Captured — \(pages.count) page\(pages.count == 1 ? "" : "s")") {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .padding(.horizontal)
            .padding(.vertical, 8)

            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Save")
                }
            }
            .disabled(isSaving)

            Button("Discard", role: .destructive) { pages = [] }
        }
    }

    /// Milestone 3's full surface: sign-in, the Scans folder picker, and real filing
    /// (`BillFilingService`, wired into `BillReviewView.save()`) are all live now. A connected
    /// session with no folder chosen yet still can't file anything, hence the extra prompt below.
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

    private var stagedSection: some View {
        // A String title plus a `footer:` closure isn't a valid `Section` overload — SwiftUI
        // only pairs a footer with a `header:` closure, not the plain-string title form.
        // Caught by the CI build (exit 65), not locally — no Swift compiler on this machine.
        Section {
            ForEach(stagedPDFs, id: \.self) { url in
                HStack {
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(.subheadline)
                        Text(PDFBuilder.fileSizeDescription(of: url))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { discard(url) }
                }
            }
        } header: {
            Text("Saved, not yet filed — \(stagedPDFs.count)")
        } footer: {
            // Honest about a real gap, not a promise this screen can't keep: there's no
            // re-open-and-refile action here yet, so these stay stuck until that's built.
            Text("Saved before Drive was connected or a Scans folder was chosen, so these weren't filed. Re-filing an already-staged bill isn't built yet.")
        }
    }

    /// Exists for exactly one reason right now: reading the real, sideloading-rewritten bundle
    /// ID off a physical device is the prerequisite for registering this app's Google OAuth
    /// client (plan §4.4's iOS caveat) — we proved the suffix is *stable* on `BillsCaptureTest`,
    /// not that it's identical for a different base bundle ID. `CopyableRow` (ported from
    /// `BillsCaptureTest`) makes that a tap-to-copy rather than a hand-retyped, one-character-off
    /// risk into Google Cloud Console.
    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            CopyableRow(label: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "unknown")
            CopyableRow(label: "Version", value: "\(shortVersion) (\(buildNumber))")
        }
    }

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
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

    private func save() {
        // Page 1 has to survive past this point for `extract-bill` (§4.2) — captured before
        // `pages` is cleared, since the assembled PDF is already compressed to the archive's
        // DPI setting, a different resolution than extraction wants. Checked before touching
        // `isSaving` — this button is only ever shown when `pages` is non-empty (capturedSection
        // above), so `nil` here would mean the button rendered for an already-empty capture
        // list, not a real save attempt.
        guard let extractionPage = pages.first else { return }

        isSaving = true
        let fileName = "bill_\(UUID().uuidString).pdf"
        do {
            let url = try PDFBuilder.makePDF(from: pages, fileName: fileName)
            pages = []
            stagedPDFs = BillPdfStore.stagedPDFs()
            pendingReview = PendingBill(pdfURL: url, extractionPage: extractionPage)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func discard(_ url: URL) {
        do {
            try BillPdfStore.delete(url)
            stagedPDFs = BillPdfStore.stagedPDFs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
