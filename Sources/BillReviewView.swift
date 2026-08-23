import SwiftUI
import UIKit

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
///
/// **Save now files to Drive for real (§4.4), ported from `BillReviewViewModel.kt`.** When
/// Drive is connected and a Scans folder is chosen, `save()` runs `BillFilingService`'s
/// two-phase pipeline: resolve the target folder (rules-cache hit, fuzzy match, or a new
/// folder), pause for §4.5's near-miss confirmation or probable-duplicate warning if either
/// applies, then upload. Falls back to the pre-Drive local-only save (`BillMetadataStore`) when
/// Drive isn't connected or no folder has been chosen yet — same as before this milestone.
struct BillReviewView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var driveAuth: DriveAuthStore
    @EnvironmentObject private var folderPreferences: DriveFolderPreferences
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

    /// The extraction's raw, un-normalized `company_name` — deliberately never touched by the
    /// `companyName` text field binding above. See `FilingDecision`'s kdoc for why the
    /// rules-cache lookup key must stay this exact string. `nil` if extraction never succeeded
    /// (the user is typing the company in by hand), in which case the trimmed field value is
    /// used as its own "raw" string.
    @State private var rawExtractedCompanyName: String?

    /// Everything a paused-for-confirmation filing attempt needs to resume — set only while a
    /// prompt below is showing. Mirrors `BillReviewViewModel.PendingFiling`.
    private struct PendingFiling {
        let accessToken: String
        let scansFolder: DriveFolder
        let context: BillFilingService.FilingContext
        let rawCompanyName: String
        let normalizedCompanyName: String
        let filingDate: SimpleDate
        let amount: Double?
        let pdfData: Data
    }

    @State private var pendingFiling: PendingFiling?
    @State private var resolvedFolderName: String?
    @State private var resolvedMatchScore: Double?

    // §4.5's near-miss confirmation ("File under existing X, or create Y?").
    @State private var nearMissExisting: String?
    @State private var nearMissScore: Double = 0
    @State private var nearMissProposed: String?

    // §4.4's probable-duplicate warning.
    @State private var duplicateFolderName: String?
    @State private var duplicateDateText: String?

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
        .alert("Similar folder found", isPresented: isNearMissPresented) {
            Button("Use \u{201C}\(nearMissExisting ?? "")\u{201D}") { onNearMissChoice(useExisting: true) }
            Button("Create \u{201C}\(nearMissProposed ?? "")\u{201D}") { onNearMissChoice(useExisting: false) }
            Button("Cancel", role: .cancel) { onNearMissChoice(useExisting: nil) }
        } message: {
            Text("This looks \(Int(nearMissScore))% similar to an existing Drive folder. File here, or create a new one?")
        }
        .alert("Possible duplicate", isPresented: isDuplicatePresented) {
            Button("Save anyway") { onDuplicateWarningChoice(saveAnyway: true) }
            Button("Cancel", role: .cancel) { onDuplicateWarningChoice(saveAnyway: false) }
        } message: {
            Text("A \(duplicateFolderName ?? "") bill dated \(duplicateDateText ?? "") already exists in this folder.")
        }
        .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Derived, not `@State` — the individual `nearMiss*` fields stay the single source of
    /// truth; this is only what the alert needs to know whether to show.
    ///
    /// `set` is deliberately a no-op, not "call the Cancel handler on dismiss": SwiftUI calls
    /// this setter with `false` after *every* button tap, including "Use existing"/"Create new"
    /// — not just when the alert is dismissed with no choice made (`.alert` has no swipe/tap-away
    /// dismissal in the first place). Each button's own action already clears `nearMiss*` itself,
    /// which is what makes `get` become `false` and the alert actually dismiss; wiring `set` to
    /// also call `onNearMissChoice` would fire it a second time on every real choice too, racing
    /// the filing `Task` that choice just kicked off against a spurious cancel.
    private var isNearMissPresented: Binding<Bool> {
        Binding(get: { nearMissExisting != nil }, set: { _ in })
    }

    private var isDuplicatePresented: Binding<Bool> {
        Binding(get: { duplicateFolderName != nil }, set: { _ in })
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
            Text(fieldsFooterText)
        }

        Section {
            Button("Discard", role: .destructive) { discard() }
        }
    }

    private var canFileToDrive: Bool {
        driveAuth.isConnected && folderPreferences.scansFolder != nil
    }

    private var fieldsFooterText: String {
        let base = "Only company is required — some documents (like a policy renewal packet) have no amount due or date printed. "
        if canFileToDrive {
            return base + "Save files this straight to your Scans folder in Drive."
        }
        return base + "Save keeps this on the phone for now — connect Google Drive and choose a Scans folder from the Bills screen to file automatically."
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
        rawExtractedCompanyName = result.companyName
        amountText = result.amount.map { String(format: "%.2f", $0) } ?? ""
        billingDateText = result.billingDate ?? ""
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        let trimmedName = companyName.trimmingCharacters(in: .whitespaces)
        let amount = Double(amountText)
        let billingDate = billingDateText.isEmpty ? nil : billingDateText

        guard canFileToDrive, let scansFolder = folderPreferences.scansFolder else {
            saveLocallyOnly(companyName: trimmedName, amount: amount, billingDate: billingDate)
            return
        }

        Task {
            do {
                let token = try await driveAuth.validAccessToken()
                let context = try await BillFilingService.loadContext(accessToken: token, scansFolder: scansFolder, driveAPI: RealDriveAPI())
                let normalized = CompanyNameNormalizer.normalize(trimmedName)
                let raw = rawExtractedCompanyName ?? trimmedName
                let filingDate = BillFileNaming.resolveFilingDate(billingDate: billingDate, captureDate: .today())
                let pdfData = try Data(contentsOf: pending.pdfURL)

                pendingFiling = PendingFiling(
                    accessToken: token,
                    scansFolder: scansFolder,
                    context: context,
                    rawCompanyName: raw,
                    normalizedCompanyName: normalized,
                    filingDate: filingDate,
                    amount: amount,
                    pdfData: pdfData
                )
                await runFilingPipeline()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    /// Pre-Drive fallback (unchanged from before this milestone): Drive isn't connected, or no
    /// Scans folder has been chosen yet.
    private func saveLocallyOnly(companyName: String, amount: Double?, billingDate: String?) {
        let metadata = BillMetadata(companyName: companyName, amount: amount, billingDate: billingDate, capturedAt: Date())
        do {
            try BillMetadataStore.save(metadata, for: pending.pdfURL)
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    /// The resumable core of Save, mirroring `BillReviewViewModel.runFilingPipeline`. Called
    /// once with no override to make the initial decision, and again from the near-miss/
    /// duplicate confirmation handlers below to resume with the user's choice already known.
    private func runFilingPipeline(folderNameOverride: String? = nil, matchScoreOverride: Double? = nil, skipDuplicateCheck: Bool = false) async {
        guard let pf = pendingFiling else { return }
        let driveAPI: DriveAPI = RealDriveAPI()

        let folderName: String
        let matchScore: Double?
        if let folderNameOverride {
            folderName = folderNameOverride
            matchScore = matchScoreOverride
        } else {
            switch BillFilingService.decide(context: pf.context, rawCompanyName: pf.rawCompanyName, normalizedCompanyName: pf.normalizedCompanyName) {
            case .needsConfirmation(let existing, let score, let proposed):
                nearMissExisting = existing
                nearMissScore = score
                nearMissProposed = proposed
                return
            case .fromRulesCache(let name):
                folderName = name
                matchScore = nil
            case .autoMatched(let name, let score):
                folderName = name
                matchScore = score
            case .newFolder(let name):
                folderName = name
                matchScore = nil
            }
        }

        if !skipDuplicateCheck {
            let candidate = FiledDocumentKey(normalizedCompanyName: folderName, filingDate: pf.filingDate)
            do {
                if let duplicate = try await BillFilingService.findDuplicate(
                    accessToken: pf.accessToken, context: pf.context, folderName: folderName, candidate: candidate, driveAPI: driveAPI
                ) {
                    resolvedFolderName = folderName
                    resolvedMatchScore = matchScore
                    duplicateFolderName = folderName
                    duplicateDateText = duplicate.filingDate.iso8601String
                    return
                }
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
                return
            }
        }

        do {
            _ = try await BillFilingService.fileDocument(
                accessToken: pf.accessToken,
                context: pf.context,
                rawCompanyName: pf.rawCompanyName,
                folderName: folderName,
                filingDate: pf.filingDate,
                amount: pf.amount,
                matchScore: matchScore,
                deviceLabel: UIDevice.current.name,
                pdfData: pf.pdfData,
                driveAPI: driveAPI
            )
            // Filed for real now — the local staged copy (and its sidecar, if any) has served
            // its purpose. Best-effort: a failed local cleanup shouldn't turn a successful Drive
            // filing into a user-facing error.
            try? BillPdfStore.delete(pending.pdfURL)
            pendingFiling = nil
            isSaving = false
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    /// `useExisting: nil` means the user dismissed the prompt without choosing — treated the
    /// same as Cancel (Android's own equivalent has no third option either).
    ///
    /// Reads `nearMiss*` into locals *before* clearing them — clearing first and then reading
    /// would always resolve "Use existing" to an empty folder name.
    private func onNearMissChoice(useExisting: Bool?) {
        let existing = nearMissExisting
        let proposed = nearMissProposed
        let score = nearMissScore
        nearMissExisting = nil
        nearMissProposed = nil

        guard let useExisting else {
            pendingFiling = nil
            isSaving = false
            return
        }
        let folderName = useExisting ? (existing ?? proposed ?? "") : (proposed ?? "")
        Task { await runFilingPipeline(folderNameOverride: folderName, matchScoreOverride: useExisting ? score : nil) }
    }

    private func onDuplicateWarningChoice(saveAnyway: Bool) {
        duplicateFolderName = nil
        guard saveAnyway, let folderName = resolvedFolderName else {
            pendingFiling = nil
            isSaving = false
            return
        }
        Task { await runFilingPipeline(folderNameOverride: folderName, matchScoreOverride: resolvedMatchScore, skipDuplicateCheck: true) }
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
