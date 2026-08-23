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
    @State private var isSettingsPresented = false

    // §4.7 PII redaction.
    @State private var pageCount = 1
    @State private var redactionRegions: [RedactionRegion] = []
    @State private var redactionEditorOpen = false
    @State private var redactionCurrentPage = 0
    @State private var redactionSuggestionsAttempted = false

    /// The extraction's raw, un-normalized `company_name` — deliberately never touched by the
    /// `companyName` text field binding above. See `FilingDecision`'s kdoc for why the
    /// rules-cache lookup key must stay this exact string. `nil` if extraction never succeeded
    /// (the user is typing the company in by hand), in which case the trimmed field value is
    /// used as its own "raw" string.
    @State private var rawExtractedCompanyName: String?

    /// Everything a paused-for-confirmation filing attempt needs to resume — set only while a
    /// prompt below is showing. Mirrors `BillReviewViewModel.PendingFiling`.
    ///
    /// **No `context` field, unlike an earlier version of this type.** §4.6 Tier 3's bounded
    /// retry needs to re-run the *whole* pipeline on each attempt, `loadContext` included —
    /// matching Android's own `runFilingPipeline`, which reloads context at the top of every
    /// call rather than trusting a snapshot that could be stale by the time a retry fires a few
    /// seconds later. `runFilingPipeline` below calls `BillFilingService.loadContext` itself.
    private struct PendingFiling {
        let accessToken: String
        let scansFolder: DriveFolder
        let rawCompanyName: String
        let normalizedCompanyName: String
        let filingDate: SimpleDate
        let amount: Double?
        let pdfData: Data
        let redactionUpdate: BillFilingService.RedactionUpdate?
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

    /// §4.6 Tier 3: "Bounded retry (3 attempts, short backoff)" — matches Android's own
    /// `FILING_MAX_ATTEMPTS`/`FILING_RETRY_DELAY_MILLIS` exactly, not a value picked
    /// independently for iOS.
    private let maxFilingAttempts = 3
    private let filingRetryDelay: UInt64 = 2_000_000_000 // 2s, in nanoseconds for Task.sleep

    /// **Redesigned 2026-08-23 from Clayton's own mockup, second in the pair with `CaptureView`.**
    /// Both mockups show the identical "Bill Scanner" + gear header, meaning this screen is no
    /// longer a pushed screen with its own nav bar and back button — confirmed explicitly, not
    /// assumed: "Save/Redact/Discard are the only way out of Review" was Clayton's own answer
    /// when asked, matching the mockup exactly. The old page-1-only image + file-size footer are
    /// gone, replaced by a horizontal strip of every page (`PageThumbnailView`, one per
    /// `pageCount`), matching the mockup's "Page 1 / Page 2 / Page 3" row.
    var body: some View {
        ZStack {
            BillScannerBackground()

            ScrollView {
                BillScannerCard {
                    BillScannerHeader(onSettings: { isSettingsPresented = true })
                    reviewContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: pending.id) {
            startExtraction()
        }
        .task(id: pending.id) {
            // Display-only -- never blocks Review from working if this fails. Defaults to 1
            // (already the initial value) so the thumbnail strip just shows one page until this
            // resolves, matching a single-page bill's own steady state.
            pageCount = (try? BillPageRenderer.pageCount(of: pending.pdfURL)) ?? 1
        }
        .fullScreenCover(isPresented: $redactionEditorOpen) {
            RedactionEditorView(
                pdfURL: pending.pdfURL,
                pageCount: pageCount,
                currentPage: $redactionCurrentPage,
                regions: $redactionRegions,
                onDone: { redactionEditorOpen = false }
            )
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
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

    // MARK: - Content

    @ViewBuilder
    private var reviewContent: some View {
        if isExtracting {
            VStack(spacing: 12) {
                ProgressView()
                Text(retryCount == 0 ? "Reading your bill…" : "Retrying (\(retryCount)/\(maxAutomaticRetries))…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 48)
        } else if let extractionError {
            VStack(spacing: 12) {
                Text(extractionError)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Retry") { retryCount = 0; startExtraction() }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
        } else {
            VStack(spacing: 20) {
                thumbnailRow
                fieldsBlock
                actionButtons
                Text(fieldsFooterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    private var thumbnailRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(0..<pageCount, id: \.self) { index in
                    PageThumbnailView(pdfURL: pending.pdfURL, page: index)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var fieldsBlock: some View {
        VStack(spacing: 12) {
            inlineField("Company:", text: $companyName, placeholder: "ABC Company")
            // Accepts "$1,234.56"-style input, not just a bare number -- `save()` strips the
            // punctuation before parsing (`parseAmount`), so this placeholder can honestly
            // invite the format Clayton's mockup shows instead of a plainer one that would
            // just risk a user typing something the old plain-`Double(_:)` parse silently
            // dropped.
            inlineField("Amount:", text: $amountText, placeholder: "$ X,XXX.XX", keyboardType: .decimalPad)
            // "MM/DD/YY" in Clayton's mockup, deliberately not copied verbatim here: the actual
            // parser (`SimpleDate.parseISO`, via `BillFileNaming.resolveFilingDate`) only
            // accepts strict `YYYY-MM-DD` -- keeping the placeholder honest about the real
            // expected format avoids a real bug where a date typed as shown silently fails to
            // parse and falls back to today's date instead.
            inlineField("Billed Date:", text: $billingDateText, placeholder: "YYYY-MM-DD")
        }
    }

    private func inlineField(_ label: String, text: Binding<String>, placeholder: String, keyboardType: UIKeyboardType = .default) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.billScannerNavy)
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4)))
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            BillScannerPillButton(
                title: "Save",
                style: .filled,
                isDisabled: companyName.trimmingCharacters(in: .whitespaces).isEmpty,
                isLoading: isSaving,
                action: save
            )
            BillScannerPillButton(title: redactionButtonLabel, style: .outlined) { redactionEditorOpen = true }
            BillScannerPillButton(title: "Discard", style: .outlined, tint: .secondary, action: discard)
        }
    }

    /// Plain "Redact" matches the mockup exactly when nothing's marked yet; the marked count
    /// is appended rather than dropped once there's something to say, since losing that signal
    /// (already useful, already device-verified working) isn't something the redesign should
    /// cost just to match a screenshot that only ever showed the empty state.
    private var redactionButtonLabel: String {
        redactionRegions.isEmpty ? "Redact" : "Redact (\(redactionRegions.count))"
    }

    private var canFileToDrive: Bool {
        driveAuth.isConnected && folderPreferences.scansFolder != nil
    }

    private var fieldsFooterText: String {
        let base = "Only company is required — some documents (like a policy renewal packet) have no amount due or date printed. "
        if canFileToDrive {
            return base + "Save files this straight to your Scans folder in Drive."
        }
        return base + "Save keeps this on the phone for now — connect Google Drive and choose a Scans folder from the Settings screen to file automatically."
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
                loadRedactionSuggestions()
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

    // MARK: - Redaction

    /// §4.7's "learned suggestion" — best-effort only, called once after extraction finishes.
    /// Silently does nothing if Drive isn't connected, no Scans folder is chosen yet, or the
    /// lookup fails for any reason — a missing suggestion just means the user draws the box by
    /// hand this once, same as any first-time bill; it must never interrupt Review.
    ///
    /// **Deliberately does not auto-open the editor**, unlike Android's own equivalent (and an
    /// earlier version of this function) — Clayton's own explicit call 2026-08-23, found live on
    /// a repeat scan of the same Citi bill: auto-jumping to the redaction screen made sense when
    /// Redact was a small link buried below the fields, but now that it's a visible button in
    /// Review's own action row, auto-navigating there the instant extraction finishes is just
    /// intrusive, not a convenience. The suggestion is still loaded into `redactionRegions` (so
    /// the "Redact (N)" button badge reflects it, and opening the editor by hand starts on the
    /// right page) — only the automatic navigation is gone.
    private func loadRedactionSuggestions() {
        guard !redactionSuggestionsAttempted else { return }
        let trimmed = companyName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, canFileToDrive, let scansFolder = folderPreferences.scansFolder else { return }
        redactionSuggestionsAttempted = true

        Task {
            do {
                let token = try await driveAuth.validAccessToken()
                let context = try await BillFilingService.loadContext(accessToken: token, scansFolder: scansFolder, driveAPI: RealDriveAPI())
                let normalized = CompanyNameNormalizer.normalize(trimmed)
                let suggested = RedactionRuleMatcher.suggestRegions(normalizedCompanyName: normalized, redactionRulesCache: context.redactionRulesCache)
                guard !suggested.isEmpty else { return }
                redactionRegions = suggested
                redactionCurrentPage = suggested.first?.page ?? 0
            } catch {
                // Non-fatal by design -- see this function's own header.
            }
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        let trimmedName = companyName.trimmingCharacters(in: .whitespaces)
        let amount = parseAmount(amountText)
        let billingDate = billingDateText.isEmpty ? nil : billingDateText

        guard canFileToDrive, let scansFolder = folderPreferences.scansFolder else {
            saveLocallyOnly(companyName: trimmedName, amount: amount, billingDate: billingDate)
            return
        }

        // §4.6 Tier 3: "persist the finished PDF + confirmed metadata locally *before*
        // attempting the Drive upload." The PDF has been durable since capture (Tier 1); this is
        // what was still missing on the Drive-connected path specifically — mirrors Android's
        // own `onSaveClick`, which calls `metadataStore.save` unconditionally before
        // `beginFiling` even checks whether Drive is reachable. A failure here aborts outright,
        // matching Android: if local staging itself can't be trusted, proceeding to a Drive
        // upload nothing local remembers happened would be worse, not safer.
        do {
            let metadata = BillMetadata(companyName: trimmedName, amount: amount, billingDate: billingDate, capturedAt: Date())
            try BillMetadataStore.save(metadata, for: pending.pdfURL)
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return
        }

        Task {
            do {
                let token = try await driveAuth.validAccessToken()
                let normalized = CompanyNameNormalizer.normalize(trimmedName)
                let raw = rawExtractedCompanyName ?? trimmedName
                let filingDate = BillFileNaming.resolveFilingDate(billingDate: billingDate, captureDate: .today())
                let pdfData = try readPdfDataForFiling()

                // Only sent when the user actually interacted with redaction this bill (see
                // `BillFilingService.RedactionUpdate`'s kdoc) -- a bill saved with the editor
                // never opened must leave any previously learned rule for this company untouched.
                let redactionUpdate: BillFilingService.RedactionUpdate? = redactionRegions.isEmpty
                    ? nil
                    : BillFilingService.RedactionUpdate(normalizedCompanyName: normalized, regions: redactionRegions)

                pendingFiling = PendingFiling(
                    accessToken: token,
                    scansFolder: scansFolder,
                    rawCompanyName: raw,
                    normalizedCompanyName: normalized,
                    filingDate: filingDate,
                    amount: amount,
                    pdfData: pdfData,
                    redactionUpdate: redactionUpdate
                )
                await runFilingPipeline()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    /// §4.7: the file that actually goes to Drive is never the original when any region has been
    /// confirmed — `PdfRedactor` rewrites every page into a fresh PDF first, so the original
    /// pixels never leave the device. Reads the untouched original straight through when there's
    /// nothing to redact, the common case (utility/insurance bills with nothing sensitive
    /// printed on the page). The redacted temp file is deleted right after its bytes are read —
    /// its only job was getting those bytes to Drive, not sticking around in staging.
    private func readPdfDataForFiling() throws -> Data {
        guard !redactionRegions.isEmpty else { return try Data(contentsOf: pending.pdfURL) }
        let redactedURL = try PdfRedactor.redact(sourcePDF: pending.pdfURL, regions: redactionRegions, profile: BillCapturePreferences.resolution)
        defer { try? FileManager.default.removeItem(at: redactedURL) }
        return try Data(contentsOf: redactedURL)
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

    /// The resumable core of Save, mirroring `BillReviewViewModel.runFilingPipeline` — including
    /// §4.6 Tier 3's bounded retry (`maxFilingAttempts`/`filingRetryDelay`), which an earlier
    /// version of this function didn't have at all: any failure anywhere in this sequence
    /// (`loadContext`, the duplicate check, or the upload itself) went straight to an error with
    /// no automatic retry, silently missing the plan's explicit "3 attempts, short backoff"
    /// requirement. `attempt` is threaded through the same recursive retry Android's own version
    /// uses, not a separate loop — a decision already made this call (a folder override from a
    /// resumed confirmation) carries through every retry rather than being re-asked.
    ///
    /// Called once with no override to make the initial decision, and again from the near-miss/
    /// duplicate confirmation handlers below to resume with the user's choice already known.
    private func runFilingPipeline(
        folderNameOverride: String? = nil,
        matchScoreOverride: Double? = nil,
        skipDuplicateCheck: Bool = false,
        attempt: Int = 1
    ) async {
        guard let pf = pendingFiling else { return }
        let driveAPI: DriveAPI = RealDriveAPI()

        do {
            // Reloaded on every attempt, deliberately not cached across retries -- matches
            // Android's own `runFilingPipeline`, which does the same for the same reason: a
            // snapshot from several seconds (and up to two retries) ago risks acting on a stale
            // folder listing or rules cache.
            let context = try await BillFilingService.loadContext(accessToken: pf.accessToken, scansFolder: pf.scansFolder, driveAPI: driveAPI)

            let folderName: String
            let matchScore: Double?
            if let folderNameOverride {
                folderName = folderNameOverride
                matchScore = matchScoreOverride
            } else {
                switch BillFilingService.decide(context: context, rawCompanyName: pf.rawCompanyName, normalizedCompanyName: pf.normalizedCompanyName) {
                case .needsConfirmation(let existing, let score, let proposed):
                    nearMissExisting = existing
                    nearMissScore = score
                    nearMissProposed = proposed
                    isSaving = false
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
                if let duplicate = try await BillFilingService.findDuplicate(
                    accessToken: pf.accessToken, context: context, folderName: folderName, candidate: candidate, driveAPI: driveAPI
                ) {
                    resolvedFolderName = folderName
                    resolvedMatchScore = matchScore
                    duplicateFolderName = folderName
                    duplicateDateText = duplicate.filingDate.iso8601String
                    isSaving = false
                    return
                }
            }

            _ = try await BillFilingService.fileDocument(
                accessToken: pf.accessToken,
                context: context,
                rawCompanyName: pf.rawCompanyName,
                folderName: folderName,
                filingDate: pf.filingDate,
                amount: pf.amount,
                matchScore: matchScore,
                deviceLabel: UIDevice.current.name,
                pdfData: pf.pdfData,
                driveAPI: driveAPI,
                redactionUpdate: pf.redactionUpdate
            )
            // Filed for real now — the local staged copy (PDF + metadata sidecar, both via
            // BillPdfStore.delete) has served its purpose. Best-effort: a failed local cleanup
            // shouldn't turn a successful Drive filing into a user-facing error.
            try? BillPdfStore.delete(pending.pdfURL)
            pendingFiling = nil
            isSaving = false
            onFinished()
        } catch {
            if attempt < maxFilingAttempts {
                try? await Task.sleep(nanoseconds: filingRetryDelay)
                await runFilingPipeline(
                    folderNameOverride: folderNameOverride,
                    matchScoreOverride: matchScoreOverride,
                    skipDuplicateCheck: skipDuplicateCheck,
                    attempt: attempt + 1
                )
            } else {
                errorMessage = "Couldn't file to Drive after a few tries. The bill is saved on this device — Save again to retry."
                isSaving = false
            }
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

    /// The mockup's own placeholder ("$ X,XXX.XX") invites `$`/`,` in the typed amount, unlike
    /// the plain-`Double(_:)` parse this used before the redesign — that would have silently
    /// dropped the whole amount the moment a user typed a `$` or a comma. Strips everything but
    /// digits and the decimal point first, so "$1,234.56" and "1234.56" both parse the same.
    private func parseAmount(_ text: String) -> Double? {
        let filtered = text.filter { $0.isNumber || $0 == "." }
        return filtered.isEmpty ? nil : Double(filtered)
    }
}

/// One page in Review's thumbnail strip — re-renders fresh from the saved PDF via
/// `BillPageRenderer` at preview quality, the same source `RedactionEditorView`'s own per-page
/// preview uses, rather than needing an in-memory capture that no longer exists after Tier 1's
/// capture-time-durable-save change.
private struct PageThumbnailView: View {
    let pdfURL: URL
    let page: Int

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(4)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 90, height: 112)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4)))

            Text("Page \(page + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: page) {
            image = try? await Task.detached(priority: .userInitiated) {
                try BillPageRenderer.renderPage(of: pdfURL, page: page, dpi: BillPageRenderer.previewDPI)
            }.value
        }
    }
}
