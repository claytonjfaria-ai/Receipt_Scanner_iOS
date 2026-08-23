import SwiftUI

/// Milestone 3 of the real iOS Bills app: capture → assemble a durable on-device PDF →
/// review + `extract-bill` → connect Google Drive → pick a Scans folder → Review's Save files
/// for real (`BillFilingService`). Falls back to the pre-Drive local sidecar (`BillMetadataStore`)
/// only when Drive isn't connected or no folder has been chosen yet.
///
/// **Redesigned 2026-08-23 from Clayton's own mockup:** the plain system `List` gave way to
/// `BillScannerBackground`/`BillScannerCard`/`BillScannerHeader` (shared with `BillReviewView`
/// and `SignInView`). Drive connection, the Scans folder, resolution, and Sign out all moved into
/// `SettingsView` behind the header's gear icon — none of that appeared in the mockup, and
/// "behind the gear icon" was Clayton's own explicit answer when asked. The old Bundle ID/Version
/// diagnostics section is gone entirely, per Clayton's explicit request — `SignInView` still
/// carries that info if it's ever needed again.
struct CaptureView: View {
    @State private var isScannerPresented = false
    @State private var errorMessage: String?
    @State private var stagedPDFs: [URL] = BillPdfStore.stagedPDFs()
    @State private var pendingReview: PendingBill?
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                BillScannerBackground()

                ScrollView {
                    BillScannerCard {
                        BillScannerHeader(onSettings: { isSettingsPresented = true })
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            // Hides the system nav bar entirely -- `BillScannerHeader` above is this screen's
            // real header now, not `.navigationTitle`. Still inside a `NavigationStack` (needed
            // for `navigationDestination` below to push Review at all), just with its own chrome
            // switched off.
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $isScannerPresented) {
                DocumentScanner(
                    onFinish: { captured in
                        isScannerPresented = false
                        handleCaptured(captured)
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
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
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

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 20) {
            scanButton

            VStack(spacing: 4) {
                Text("Scan")
                    .font(.title3.bold())
                    .foregroundStyle(Color.billScannerNavy)
                Text("Tap the scan button to start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            stagedArea
        }
        .padding(24)
    }

    private var scanButton: some View {
        Button {
            isScannerPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.billScannerTeal.opacity(0.15))
                    .frame(width: 150, height: 150)
                Circle()
                    .fill(Color.billScannerTeal)
                    .frame(width: 116, height: 116)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 42))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    /// §4.6 Tier 3's own on-screen surface: "a small '1 bill not yet filed' indicator ...
    /// retryable on next app open." Empty state matches the mockup exactly (a dashed
    /// placeholder); populated state is Clayton's own extrapolation — neither mockup showed
    /// this state, so it's a reasonable first pass, not a literal match, and easy to revise
    /// once he's seen it for real. A `List` here, not a plain `VStack`, specifically so
    /// swipe-to-delete (`.swipeActions`, List-only in SwiftUI) still works while
    /// `.scrollDisabled(true)` lets the outer `ScrollView` own all the actual scrolling.
    @ViewBuilder
    private var stagedArea: some View {
        if stagedPDFs.isEmpty {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.systemGray4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
                .frame(height: 90)
                .overlay {
                    Text("Your scanned bills will appear here")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved, not yet filed — \(stagedPDFs.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                List {
                    ForEach(stagedPDFs, id: \.self) { url in
                        Button {
                            openStagedBill(url)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.billScannerNavy)
                                    Text(PDFBuilder.fileSizeDescription(of: url))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button("Delete", role: .destructive) { discard(url) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(stagedPDFs.count) * 76)
            }
        }
    }

    // MARK: - Actions

    /// PLAN-MOBILE-BILLS-CAPTURE.md §4.6 Tier 1: "app-scoped save the instant the scanner
    /// returns" — no user confirmation step in between, matching the Receipts fix this tier
    /// reuses verbatim, and matching Android's own Bills flow (scanner finishes → straight to
    /// Review, no separate "confirm these pages" screen).
    private func handleCaptured(_ images: [UIImage]) {
        // Defensive, not expected in practice — VisionKit's own delegate contract is that
        // `didFinishWith` only fires with at least one page; `onCancel` covers the empty case.
        guard let extractionPage = images.first else { return }

        let fileName = "bill_\(UUID().uuidString).pdf"
        do {
            let url = try PDFBuilder.makePDF(from: images, fileName: fileName)
            stagedPDFs = BillPdfStore.stagedPDFs()
            pendingReview = PendingBill(pdfURL: url, extractionPage: extractionPage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// §4.6 Tier 3's "retryable on next app open" — reconstructs a `PendingBill` for an already
    /// on-disk PDF with no in-memory capture to fall back on. Re-renders page 1 fresh via
    /// `BillPageRenderer` rather than trying to keep a `UIImage` alive across a process the OS
    /// may have killed in between.
    private func openStagedBill(_ url: URL) {
        do {
            let page = try BillPageRenderer.renderPage(of: url, page: 0, dpi: BillPageRenderer.extractionRenderDPI)
            pendingReview = PendingBill(pdfURL: url, extractionPage: page)
        } catch {
            errorMessage = error.localizedDescription
        }
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
