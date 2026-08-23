import Foundation

/// A port of Android `Receipt_Scanner`'s `DriveBillFilingService.kt` — §4.4's Drive-facing
/// orchestration over the already-ported pure logic (`FilingDecision`, `FolderFuzzyMatcher`,
/// `BillFileNaming`, `DuplicateDetector`, `RulesLearnedFile`).
///
/// **Two-phase by design**, mirroring §4.5's "ask before an ambiguous filing, don't ask for a
/// plain one": `loadContext` + `decide` only read from Drive, so `BillReviewView` can show the
/// near-miss confirmation (and, after that, the probable-duplicate warning) *before* anything is
/// written. `fileDocument` does the actual write — folder creation, upload, `Rules_Learned.json`
/// update — once a decision, resolved automatically or confirmed by the user, is in hand.
///
/// **Deliberately smaller than Android's version at this milestone:** no redaction parameter —
/// iOS hasn't built §4.7 (PII redaction) yet. `redactionRulesCache` is still read and always
/// written back completely unchanged on every filing, though — `RulesLearnedFile`'s own kdoc is
/// explicit that omitting the key on write would silently erase whatever Android already learned
/// for a shared household archive, not just leave it untouched.
enum BillFilingService {
    private static let rulesLearnedFileName = "Rules_Learned.json"

    // `fileprivate`, not `private`: the `DriveFile.filedDocumentKey` extension at the bottom of
    // this file needs `propertyCompanyName`/`propertyBillingDate` too, and Swift's `private`
    // only reaches extensions of *this* type, not another type in the same file.
    fileprivate static let propertyCompanyName = "company_name"
    fileprivate static let propertyBillingDate = "billing_date"
    private static let propertyAmount = "amount"
    private static let propertyMatchScore = "match_score"
    private static let propertyFolderCreated = "folder_created"
    private static let propertyFiledByDevice = "filed_by_device"

    struct FilingContext {
        let scansFolder: DriveFolder
        let existingFolders: [DriveFolder]
        let rulesFileID: String?
        let rulesCache: [String: String]
        let redactionRulesCache: [String: [RedactionRegion]]
    }

    struct FilingResult {
        let folderName: String
        let fileName: String
        let folderCreated: Bool
    }

    /// The one network-heavy read of a filing attempt: the `Scans/` root's subfolders (for
    /// fuzzy-matching) and its `Rules_Learned.json`, if any. A corrupt or unreadable rules file
    /// degrades to an empty cache rather than blocking filing — a bad file shouldn't strand every
    /// future bill from every company.
    static func loadContext(accessToken: String, scansFolder: DriveFolder, driveAPI: DriveAPI) async throws -> FilingContext {
        let folders = try await driveAPI.listSubfolders(accessToken: accessToken, parentFolderID: scansFolder.id)
        let rulesFile = try await driveAPI.findFile(accessToken: accessToken, parentFolderID: scansFolder.id, name: rulesLearnedFileName)

        var rulesCache: [String: String] = [:]
        var redactionRulesCache: [String: [RedactionRegion]] = [:]
        if let rulesFile,
           let content = try? await driveAPI.readFileContent(accessToken: accessToken, fileID: rulesFile.id),
           let data = content.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(RulesLearnedFile.self, from: data) {
            rulesCache = parsed.rules
            redactionRulesCache = parsed.redactionRules
        }

        return FilingContext(
            scansFolder: scansFolder,
            existingFolders: folders,
            rulesFileID: rulesFile?.id,
            rulesCache: rulesCache,
            redactionRulesCache: redactionRulesCache
        )
    }

    /// See `FilingDecision`'s kdoc for why `rawCompanyName` must stay the extraction's
    /// un-normalized string.
    static func decide(context: FilingContext, rawCompanyName: String, normalizedCompanyName: String) -> FilingDecision {
        FilingDecision.decide(
            rawCompanyName: rawCompanyName,
            normalizedCompanyName: normalizedCompanyName,
            rulesCache: context.rulesCache,
            existingFolders: context.existingFolders.map(\.name)
        )
    }

    /// §4.4's probable-duplicate check against the resolved target folder's existing files — `nil`
    /// if that folder doesn't exist yet (nothing to duplicate) or no match was found.
    static func findDuplicate(
        accessToken: String,
        context: FilingContext,
        folderName: String,
        candidate: FiledDocumentKey,
        driveAPI: DriveAPI
    ) async throws -> FiledDocumentKey? {
        guard let folder = context.existingFolders.first(where: { $0.name == folderName }) else { return nil }
        let files = try await driveAPI.listFiles(accessToken: accessToken, parentFolderID: folder.id)
        let existing = files.compactMap(\.filedDocumentKey)
        return DuplicateDetector.findProbableDuplicate(candidate: candidate, existingInTargetFolder: existing)
    }

    /// Uploads `pdfData` into (creating first if necessary) `folderName`, records §4.5's audit
    /// trail in `appProperties` (match score, whether a new folder was created, the filing
    /// device), and learns `rawCompanyName -> folderName` into `Rules_Learned.json` so the same
    /// raw extraction skips straight to this folder next time.
    static func fileDocument(
        accessToken: String,
        context: FilingContext,
        rawCompanyName: String,
        folderName: String,
        filingDate: SimpleDate,
        amount: Double?,
        matchScore: Double?,
        deviceLabel: String,
        pdfData: Data,
        driveAPI: DriveAPI
    ) async throws -> FilingResult {
        let existingFolder = context.existingFolders.first(where: { $0.name == folderName })
        let targetFolder: DriveFolder
        let folderCreated: Bool
        if let existingFolder {
            targetFolder = existingFolder
            folderCreated = false
        } else {
            targetFolder = try await driveAPI.createFolder(accessToken: accessToken, parentFolderID: context.scansFolder.id, name: folderName)
            folderCreated = true
        }

        let fileName = BillFileNaming.buildFilingFileName(folderName: folderName, filingDate: filingDate)
        var appProperties: [String: String] = [
            propertyCompanyName: folderName,
            propertyBillingDate: filingDate.iso8601String,
            propertyFolderCreated: String(folderCreated),
            propertyFiledByDevice: deviceLabel,
        ]
        if let amount { appProperties[propertyAmount] = String(amount) }
        if let matchScore { appProperties[propertyMatchScore] = String(matchScore) }

        _ = try await driveAPI.uploadFile(
            accessToken: accessToken,
            parentFolderID: targetFolder.id,
            fileName: fileName,
            mimeType: "application/pdf",
            content: pdfData,
            appProperties: appProperties
        )

        let updatedRules = FilingDecision.withRuleLearned(context.rulesCache, rawCompanyName: rawCompanyName, folderName: folderName)
        try await writeRulesLearned(accessToken: accessToken, context: context, rules: updatedRules, redactionRules: context.redactionRulesCache, driveAPI: driveAPI)

        return FilingResult(folderName: folderName, fileName: fileName, folderCreated: folderCreated)
    }

    private static func writeRulesLearned(
        accessToken: String,
        context: FilingContext,
        rules: [String: String],
        redactionRules: [String: [RedactionRegion]],
        driveAPI: DriveAPI
    ) async throws {
        let file = RulesLearnedFile(updatedAt: RulesLearnedFile.nowIsoSeconds(), rules: rules, redactionRules: redactionRules)
        let content = String(data: try JSONEncoder().encode(file), encoding: .utf8) ?? "{}"
        if let fileID = context.rulesFileID {
            try await driveAPI.writeFileContent(accessToken: accessToken, fileID: fileID, content: content)
        } else {
            _ = try await driveAPI.uploadFile(
                accessToken: accessToken,
                parentFolderID: context.scansFolder.id,
                fileName: rulesLearnedFileName,
                mimeType: "application/json",
                content: Data(content.utf8),
                appProperties: [:]
            )
        }
    }
}

/// `appProperties` only round-trips what `BillFilingService.fileDocument` itself wrote — a file
/// some other tool dropped into the folder without those keys is silently excluded from
/// duplicate-checking rather than crashing it.
private extension DriveFile {
    var filedDocumentKey: FiledDocumentKey? {
        guard
            let companyName = appProperties[BillFilingService.propertyCompanyName],
            let billingDateString = appProperties[BillFilingService.propertyBillingDate],
            let date = SimpleDate.parseISO(billingDateString)
        else { return nil }
        return FiledDocumentKey(normalizedCompanyName: companyName, filingDate: date)
    }
}
