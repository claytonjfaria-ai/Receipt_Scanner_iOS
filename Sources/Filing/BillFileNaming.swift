import Foundation

/// A port of Android `Receipt_Scanner`'s `BillFileNaming.kt`.
///
/// Plan §4.4: "The filename always needs a date even though `billing_date` doesn't always exist
/// (reference documents, per §4.2) — when it's null, fall back to the phone's capture date rather
/// than blocking the save or making the date field mandatory on the review screen."
enum BillFileNaming {
    /// `billingDate` is Review's free-text field — expected `YYYY-MM-DD` when present, but
    /// user-edited and not validated there. An unparseable non-blank value also falls back to
    /// `captureDate` rather than failing filing over a typo'd date.
    static func resolveFilingDate(billingDate: String?, captureDate: SimpleDate) -> SimpleDate {
        guard
            let trimmed = billingDate?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty,
            let parsed = SimpleDate.parseISO(trimmed)
        else { return captureDate }
        return parsed
    }

    /// `Scans/<Company>/<Company>_<YYYYMMDD>.pdf` — the convention `scanner-to-PDF`'s Organizer
    /// already produces. `folderName` must be the **resolved** folder name from a `FilingDecision`,
    /// not necessarily a fresh `CompanyNameNormalizer.normalize` output — a fuzzy-matched existing
    /// folder's exact spelling/casing is what should end up in the filename, not the freshly
    /// extracted name's, matching the real Python's behavior (`main.py::_process_item`).
    static func buildFilingFileName(folderName: String, filingDate: SimpleDate) -> String {
        "\(folderName)_\(filingDate.compactString).pdf"
    }

    /// The parent folder path within `Scans/` for a filed document.
    static func buildFilingFolderPath(folderName: String) -> String {
        "Scans/\(folderName)"
    }
}
