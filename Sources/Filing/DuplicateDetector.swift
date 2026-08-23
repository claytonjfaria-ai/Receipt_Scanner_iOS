import Foundation

/// A port of Android `Receipt_Scanner`'s `DuplicateDetector.kt`.
///
/// Plan §4.4's probable-duplicate detection: "the idempotency key from the upload step only
/// catches a retried upload of the *same* capture session; it does nothing for the same paper
/// bill scanned twice on two different days." Matched on the target folder's existing
/// `appProperties` (`company_name` + `billing_date`), not filename parsing.
///
/// A hit is a warning, not a block — Review surfaces it and lets the user save anyway
/// (installment bills, corrected re-issues legitimately share company + date).
///
/// **Caveat carried over from §4.4:** this is date-based, and an undated reference document's
/// date is already `BillFileNaming.resolveFilingDate`'s capture-date fallback by the time it
/// reaches here — so a genuine duplicate scan of the same undated packet on a *different* day
/// won't be caught. Not solved here; same trade-off the plan accepts for filing without a real
/// date at all.
struct FiledDocumentKey: Equatable {
    let normalizedCompanyName: String
    let filingDate: SimpleDate
}

enum DuplicateDetector {
    /// `existingInTargetFolder` is the already-filed documents to check against — i.e. the
    /// target `Scans/<Company>/` folder's contents, read from each file's `appProperties`.
    static func findProbableDuplicate(candidate: FiledDocumentKey, existingInTargetFolder: [FiledDocumentKey]) -> FiledDocumentKey? {
        existingInTargetFolder.first { $0 == candidate }
    }
}
