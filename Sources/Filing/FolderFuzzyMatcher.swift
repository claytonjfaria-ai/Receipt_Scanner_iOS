import Foundation

enum MatchClassification: Equatable { case autoMatch, nearMiss, noMatch }

struct FolderMatch: Equatable {
    let folderName: String
    let score: Double

    /// §4.5's three-way filing decision. The 70–85% near-miss band is "similar enough to be
    /// plausible, not similar enough to auto-match."
    var classification: MatchClassification {
        if score >= FolderFuzzyMatcher.autoMatchThreshold { return .autoMatch }
        if score >= FolderFuzzyMatcher.nearMissFloor { return .nearMiss }
        return .noMatch
    }
}

/// A port of Android `Receipt_Scanner`'s `FolderFuzzyMatcher.kt` — the hand-rolled stand-in for
/// `rapidfuzz.fuzz.ratio()` plan §4.4 specifies: not Levenshtein or Jaro-Winkler, but normalized
/// **Indel distance** (`ratio = 200 * LCS_length(a, b) / (len(a) + len(b))`). Matching this exact
/// formula, not just "a" fuzzy-match algorithm, is what preserves the 85% threshold's real-world
/// meaning against years of existing `Scans/` folder names.
///
/// Both inputs are expected to already be `CompanyNameNormalizer`-normalized. Scores
/// lowercase-vs-lowercase, matching the real Python `find_matching_folder`'s behavior, confirmed
/// against source on the Android side.
enum FolderFuzzyMatcher {
    static let autoMatchThreshold = 85.0
    static let nearMissFloor = 70.0

    /// Two empty strings are defined as a perfect match (100.0) rather than dividing by zero.
    static func indelRatio(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 100.0 }
        let lcs = longestCommonSubsequenceLength(Array(a), Array(b))
        return 200.0 * Double(lcs) / Double(a.count + b.count)
    }

    /// Standard O(n·m) LCS-length DP table. Indexed 0-based and guarded on empty input up front —
    /// Kotlin's `1..0` range is silently empty, but Swift's `1...0` **traps at runtime**, so the
    /// direct one-line translation of the Kotlin loop bounds would have crashed on any empty
    /// string, which `indelRatio` can otherwise reach via `bestMatch` on an empty folder name.
    private static func longestCommonSubsequenceLength(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0..<a.count {
            for j in 0..<b.count {
                if a[i] == b[j] {
                    table[i + 1][j + 1] = table[i][j] + 1
                } else {
                    table[i + 1][j + 1] = max(table[i][j + 1], table[i + 1][j])
                }
            }
        }
        return table[a.count][b.count]
    }

    /// Best-scoring existing folder for `normalizedCompanyName`, or `nil` if `existingFolders` is
    /// empty.
    ///
    /// **Not** `existingFolders.map(...).max(by:)`. Swift's `max(by:)` returns the *last*
    /// maximal element on a tie; Kotlin's `maxByOrNull` (what Android uses) keeps the *first* —
    /// matching the real Python's strict `score > best_score` comparison. Using Swift's own
    /// `max(by:)` here would silently pick a different folder than Android on a tied score,
    /// exactly the kind of platform drift plan §8's shared-fixture-test mitigation exists to
    /// catch — so it's avoided at the source instead of relying only on that test to notice.
    static func bestMatch(normalizedCompanyName: String, existingFolders: [String]) -> FolderMatch? {
        let lowered = normalizedCompanyName.lowercased()
        var best: FolderMatch?
        for folder in existingFolders {
            let candidate = FolderMatch(folderName: folder, score: indelRatio(lowered, folder.lowercased()))
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }
        return best
    }
}
