import SwiftUI

/// Milestone 1 of the real iOS Bills app: capture → assemble a durable on-device PDF.
/// No `extract-bill` call, no Drive OAuth, no filing — those are later milestones, built up
/// in the same order the Android build followed (plan §4.1 → §4.2 → §4.4).
struct CaptureView: View {
    @State private var pages: [UIImage] = []
    @State private var isScannerPresented = false
    @State private var errorMessage: String?
    @State private var resolution = BillCapturePreferences.resolution
    @State private var stagedPDFs: [URL] = BillPdfStore.stagedPDFs()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                if !pages.isEmpty {
                    capturedSection
                }
                resolutionSection
                if !stagedPDFs.isEmpty {
                    stagedSection
                }
            }
            .navigationTitle("Bills")
            .toolbar {
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
            }
            .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
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

            Button("Scan more pages") { isScannerPresented = true }

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
        Section("Saved, not yet filed — \(stagedPDFs.count)") {
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
        } footer: {
            Text("Filing to Drive isn't built yet — these stay on-device until that milestone lands.")
        }
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        let fileName = "bill_\(UUID().uuidString).pdf"
        do {
            let url = try PDFBuilder.makePDF(from: pages, fileName: fileName)
            pages = []
            stagedPDFs = BillPdfStore.stagedPDFs()
            _ = url // reserved for the review-screen handoff in the next milestone
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
