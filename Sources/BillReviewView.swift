import SwiftUI

/// A captured, saved bill waiting for review — the handoff between `CaptureView` and
/// `BillReviewView`. Carries both the durable archive PDF (already on disk, per `BillPdfStore`)
/// and the original first-page capture, kept in memory only for the `extract-bill` call
/// (§4.2: extraction reads a different resolution than the archive, so the raw capture has to
/// survive past the point the archive PDF was assembled).
struct PendingBill: Identifiable, Hashable {
    let id = UUID()
    let pdfURL: URL
    let extractionPage: UIImage

    // `navigationDestination(item:)` needs `Hashable`, not just `Identifiable` — caught by
    // CI (exit 65), not locally. Derived on `id` alone: `UIImage` doesn't reliably conform to
    // Hashable/Equatable, and identity is all this comparison actually needs.
    static func == (lhs: PendingBill, rhs: PendingBill) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Plan §4.3: "much simpler than receipts' — no line items to edit... let the user correct
/// any field; confirm." §4.6 Tier 2's bounded retry: 2 automatic retries, 3s delay, then a
/// manual Retry button — matching the delay Android's actual implementation settled on.
struct BillReviewView: View {
    @EnvironmentObject private var auth: AuthStore
    let pending: PendingBill
    let onFinished: () -> Void

    @State private var companyName = ""
    @State private var amountText = ""
    @State private var billingDateText = ""
    @State private var isExtracting = true
    @State private var extractionError: String?
    @State private var retryCount = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let maxAutomaticRetries = 2
    private let retryDelay: UInt64 = 3_000_000_000 // 3s, in nanoseconds for Task.sleep

    var body: some View {
        Form {
            Section {
                Image(uiImage: pending.extractionPage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .padding(8)
            } footer: {
                Text(PDFBuilder.fileSizeDescription(of: pending.pdfURL))
            }

            if isExtracting {
                Section {
                    HStack {
                        ProgressView()
                        Text(retryCount == 0 ? "Reading your bill…" : "Retrying (\(retryCount)/\(maxAutomaticRetries))…")
                    }
                }
            } else if let extractionError {
                Section {
                    Text(extractionError)
                        .foregroundStyle(.red)
                    Button("Retry") { retryCount = 0; startExtraction() }
                }
            } else {
                fieldsSection
            }
        }
        .navigationTitle("Review bill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { save() }
                    .disabled(isExtracting || isSaving || companyName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task(id: pending.id) {
            startExtraction()
        }
        .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // Two sibling `Section`s — needs `@ViewBuilder` explicitly. Unlike `body`, a plain
    // computed `some View` property isn't a ViewBuilder context on its own; every other
    // section in this file is a single expression and doesn't need this.
    @ViewBuilder
    private var fieldsSection: some View {
        Section {
            TextField("Company", text: $companyName)
            TextField("Amount (optional)", text: $amountText)
                .keyboardType(.decimalPad)
            TextField("Billing date, e.g. 2026-08-12 (optional)", text: $billingDateText)
        } footer: {
            // Found live 2026-08-23: a real test round scanned and saved a bill, then couldn't
            // find it in Drive — reasonably, since nothing here says Save doesn't file there
            // yet. Made explicit rather than left implicit in the Bills screen's own footer,
            // since this is the screen where that expectation actually forms.
            Text("Only company is required — some documents (like a policy renewal packet) have no amount due or date printed. Save keeps this on the phone for now — filing to Drive isn't built yet.")
        }

        Section {
            Button("Discard", role: .destructive) { discard() }
        }
    }

    // MARK: - Extraction

    private func startExtraction() {
        isExtracting = true
        extractionError = nil

        Task {
            do {
                let token = try await auth.validAccessToken()
                let result = try await ExtractBillClient.extract(page: pending.extractionPage, accessToken: token)
                apply(result)
                isExtracting = false
            } catch {
                if retryCount < maxAutomaticRetries {
                    retryCount += 1
                    try? await Task.sleep(nanoseconds: retryDelay)
                    startExtraction()
                } else {
                    isExtracting = false
                    extractionError = error.localizedDescription
                }
            }
        }
    }

    private func apply(_ result: BillExtractionResult) {
        companyName = result.companyName
        amountText = result.amount.map { String(format: "%.2f", $0) } ?? ""
        billingDateText = result.billingDate ?? ""
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        let trimmedName = companyName.trimmingCharacters(in: .whitespaces)
        let metadata = BillMetadata(
            companyName: trimmedName,
            amount: Double(amountText),
            billingDate: billingDateText.isEmpty ? nil : billingDateText,
            capturedAt: Date()
        )
        do {
            try BillMetadataStore.save(metadata, for: pending.pdfURL)
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func discard() {
        do {
            try BillPdfStore.delete(pending.pdfURL)
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
