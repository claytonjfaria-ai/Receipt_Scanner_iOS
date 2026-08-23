import Foundation

/// A port of Android `Receipt_Scanner`'s `FilingDecision.kt`.
///
/// Mirrors `scanner-to-PDF`'s `organizer/main.py::_process_item` filing-decision order: an exact
/// **raw, un-normalized** company-string hit in the rules cache short-circuits straight to a
/// folder, bypassing fuzzy matching entirely — that's why a real `Rules_Learned.json` sample has
/// an entry like `"R/O Magic": "Quality_First"`, a raw OCR string that would never fuzzy-match
/// `Quality_First` on its own. Only when there's no rules-cache hit does fuzzy matching against
/// existing folders run, falling back to the freshly normalized name when nothing scores high
/// enough.
///
/// **Where mobile deliberately diverges from Python, per §4.5:** Python silently creates a new
/// folder whenever nothing scores >= 85%, full stop. Mobile adds a near-miss band (70–85%) where
/// Review must ask the user before filing, since a silently-created near-duplicate folder is the
/// filing error that's genuinely painful to unwind months later.
enum FilingDecision: Equatable {
    /// An exact raw-string hit in `Rules_Learned.json` — a previously human-confirmed mapping.
    case fromRulesCache(folderName: String)
    /// Fuzzy score >= 85% against an existing folder — files automatically, no prompt.
    case autoMatched(folderName: String, score: Double)
    /// Fuzzy score in [70, 85) — §4.5's near-miss confirmation must run before this is trusted.
    case needsConfirmation(existingFolderName: String, score: Double, proposedNewFolderName: String)
    /// No rules-cache hit and no fuzzy match >= 70% (or no existing folders at all).
    case newFolder(folderName: String)

    /// The folder this document should be filed under, if accepted as-is. For
    /// `.needsConfirmation`, defaults to the existing folder — matches §4.5's framing of the
    /// prompt (existing folder named first) and the real Python's own "match wins when a match
    /// exists at all" default.
    var folderName: String {
        switch self {
        case .fromRulesCache(let name): return name
        case .autoMatched(let name, _): return name
        case .needsConfirmation(let existing, _, _): return existing
        case .newFolder(let name): return name
        }
    }

    /// `rawCompanyName` is the extraction's raw, unmodified `company_name` (the rules-cache
    /// lookup key — must stay un-normalized, see this file's header). `normalizedCompanyName`
    /// should already be `CompanyNameNormalizer.normalize`'s output. `existingFolders` is the
    /// target `Scans/` tree's current subfolder listing.
    static func decide(
        rawCompanyName: String,
        normalizedCompanyName: String,
        rulesCache: [String: String],
        existingFolders: [String]
    ) -> FilingDecision {
        if let cached = rulesCache[rawCompanyName] {
            return .fromRulesCache(folderName: cached)
        }

        guard
            let best = FolderFuzzyMatcher.bestMatch(normalizedCompanyName: normalizedCompanyName, existingFolders: existingFolders)
        else { return .newFolder(folderName: normalizedCompanyName) }

        switch best.classification {
        case .autoMatch:
            return .autoMatched(folderName: best.folderName, score: best.score)
        case .nearMiss:
            return .needsConfirmation(existingFolderName: best.folderName, score: best.score, proposedNewFolderName: normalizedCompanyName)
        case .noMatch:
            return .newFolder(folderName: normalizedCompanyName)
        }
    }

    /// After a document is actually filed, the raw extracted string that led there is remembered
    /// so the same phrasing skips fuzzy matching next time (`add_rule` in the real Python).
    /// Returns a new dictionary rather than mutating — matches this project's immutable-update
    /// convention; the caller writes the result back to the Drive-resident `Rules_Learned.json`.
    static func withRuleLearned(_ rulesCache: [String: String], rawCompanyName: String, folderName: String) -> [String: String] {
        var updated = rulesCache
        updated[rawCompanyName] = folderName
        return updated
    }
}
