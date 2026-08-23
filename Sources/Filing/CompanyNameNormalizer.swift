import Foundation

/// A port of Android `Receipt_Scanner`'s `CompanyNameNormalizer.kt`, itself a verified
/// line-for-line port of `scanner-to-PDF`'s `organizer/rules_engine.py::normalize_company_name`
/// (plan §4.4). Ported from the Kotlin, not re-derived from the Python independently — the
/// Kotlin version is already cross-checked against real `Rules_Learned.json` entries
/// (`DUKE ENERGY` -> `Duke_Energy`, `MetLife` -> `Metlife`, `newrez.` -> `Newrez`,
/// `City of Winter Garden` -> `City_Of_Winter_Garden`), which this file's tests reuse as
/// regression cases so both platforms stay provably in sync, not just similarly-shaped.
///
/// Order matters and mirrors the Kotlin/Python exactly: strip a trailing legal suffix first (so
/// `"Acme, LLC"` doesn't have its comma-and-suffix survive later punctuation stripping in a
/// mangled form), then drop characters Windows can't have in a filename, then turn `&` into
/// `And` (before general punctuation stripping would otherwise just delete it), then strip
/// everything else that isn't a letter/digit/space, then Python-style title-case, then join with
/// underscores, then collapse any doubled underscore, then truncate to 50 characters.
///
/// Uses `NSRegularExpression`, not Swift's newer `Regex`/`String.replacing(_:with:)` — several of
/// those convenience APIs need iOS 17, and this app's deployment target is 16.0 (see
/// `CaptureView.swift`'s own `onChange` comment for the same constraint hit before).
enum CompanyNameNormalizer {
    private static let legalSuffixes = ["LLC", "Inc", "Corp", "Ltd", "Co", "NA", "N.A.", "PLC", "Company"]
    private static let windowsIllegalChars: Set<Character> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
    private static let maxLength = 50

    /// `[,\s]+(suffix)\.?\s*$`, case-insensitive — a suffix only strips when preceded by a comma
    /// or whitespace, matching the Python pattern exactly.
    private static let legalSuffixRegex: NSRegularExpression = {
        let escaped = legalSuffixes.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        // force-try is fine here: pattern is a compile-time constant, a failure would be a coding error, not a runtime condition.
        return try! NSRegularExpression(pattern: "[,\\s]+(\(escaped))\\.?\\s*$", options: .caseInsensitive)
    }()

    private static let nonAlphanumericOrSpace = try! NSRegularExpression(pattern: "[^a-zA-Z0-9\\s]")
    private static let repeatedUnderscores = try! NSRegularExpression(pattern: "_+")

    static func normalize(_ raw: String) -> String {
        var name = stripLegalSuffixes(raw)
        name = String(name.filter { !windowsIllegalChars.contains($0) })
        name = name.replacingOccurrences(of: "&", with: "And")
        name = replaceAll(nonAlphanumericOrSpace, in: name, with: "")
        name = pythonTitleCase(name.trimmingCharacters(in: .whitespaces))
        name = name.replacingOccurrences(of: " ", with: "_")
        name = replaceAll(repeatedUnderscores, in: name, with: "_")
        return String(name.prefix(maxLength))
    }

    private static func stripLegalSuffixes(_ name: String) -> String {
        replaceAll(legalSuffixRegex, in: name, with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func replaceAll(_ regex: NSRegularExpression, in string: String, with template: String) -> String {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: template)
    }

    /// Python `str.title()` semantics, not "capitalize each space-separated word": word
    /// boundaries are any non-letter (digits count as separators too), so `"MetLife"` is one
    /// unbroken letters-only run and title-cases to `"Metlife"` — matching the real archive's
    /// actual folder name, not the naive per-word-capitalize result.
    private static func pythonTitleCase(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var previousWasLetter = false
        for char in input {
            if char.isLetter {
                result.append(previousWasLetter ? char.lowercased() : char.uppercased())
                previousWasLetter = true
            } else {
                result.append(char)
                previousWasLetter = false
            }
        }
        return result
    }
}
