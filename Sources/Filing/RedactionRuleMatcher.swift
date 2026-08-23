import Foundation

/// A port of Android `Receipt_Scanner`'s `RedactionRuleMatcher.kt`. Reuses
/// `FolderFuzzyMatcher.bestMatch` against `redactionRulesCache`'s own keys — the same matcher
/// §4.4's folder-filing decision already uses, not a second matching system, per §4.7's own
/// explicit instruction.
///
/// **Only the auto-match threshold applies here — there is no near-miss band for a suggestion.**
/// §4.5's near-miss confirmation exists because an auto-*filed* near-match is hard to unwind
/// months later. A redaction suggestion is never applied silently either way (§4.7: "always shown
/// as a confirmable overlay, never auto-applied"), so a lower-confidence guess costs nothing worse
/// than one extra tap to clear it — but a rule below the auto-match bar is more likely to be a
/// different company than the one being reviewed, so it's better to show no suggestion at all
/// than a wrong one dressed up as a match.
enum RedactionRuleMatcher {
    static func suggestRegions(normalizedCompanyName: String, redactionRulesCache: [String: [RedactionRegion]]) -> [RedactionRegion] {
        if redactionRulesCache.isEmpty { return [] }
        if let exact = redactionRulesCache[normalizedCompanyName] { return exact } // Exact hit -- skip the LCS scan.

        guard
            let best = FolderFuzzyMatcher.bestMatch(normalizedCompanyName: normalizedCompanyName, existingFolders: Array(redactionRulesCache.keys)),
            best.score >= FolderFuzzyMatcher.autoMatchThreshold
        else { return [] }
        return redactionRulesCache[best.folderName] ?? []
    }

    /// Replaces whatever was learned for `normalizedCompanyName` with the regions actually
    /// confirmed on this bill. Only called when the user touched redaction this time — a bill
    /// filed with no redaction interaction must never clobber a company's existing learned rule
    /// back to nothing (mirrors `FilingDecision.withRuleLearned`'s own immutable-update shape).
    static func withRuleLearned(_ redactionRulesCache: [String: [RedactionRegion]], normalizedCompanyName: String, regions: [RedactionRegion]) -> [String: [RedactionRegion]] {
        var updated = redactionRulesCache
        updated[normalizedCompanyName] = regions
        return updated
    }
}
