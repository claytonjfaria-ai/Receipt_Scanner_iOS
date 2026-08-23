import Foundation

/// A port of Android `Receipt_Scanner`'s `RulesLearnedFile.kt`.
///
/// The exact on-disk shape of `Rules_Learned.json` (`organizer/rules_engine.py::save_rules`):
/// ```json
/// {"version": "1.0", "updated_at": "2026-05-22T23:38:59", "rules": {"DUKE ENERGY": "Duke_Energy"}}
/// ```
/// Plan §4.4: "Decided: adopt the existing file as-is, not reset" — this model exists to read
/// that real file unchanged, not to define a new schema. `rules` maps a raw, un-normalized
/// extracted company string to its resolved folder name (see `FilingDecision`'s header for why
/// the lookup key must stay un-normalized).
///
/// `redactionRules` (§4.7, added on Android 2026-08-22) is modeled here even though iOS doesn't
/// write to it yet — see `RedactionRegion.swift` for why omitting it would be a silent-data-loss
/// bug, not just an unused field.
struct RulesLearnedFile: Codable {
    static let schemaVersion = "1.0"

    var version: String
    var updatedAt: String
    var rules: [String: String]
    var redactionRules: [String: [RedactionRegion]]

    enum CodingKeys: String, CodingKey {
        case version
        case updatedAt = "updated_at"
        case rules
        case redactionRules = "redaction_rules"
    }

    init(
        version: String = RulesLearnedFile.schemaVersion,
        updatedAt: String,
        rules: [String: String] = [:],
        redactionRules: [String: [RedactionRegion]] = [:]
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.rules = rules
        self.redactionRules = redactionRules
    }

    /// Custom, not synthesized: a file written before `redaction_rules` existed (or, in
    /// principle, before `rules` was ever populated) must decode cleanly with empty defaults for
    /// whichever keys are missing, rather than throwing `DecodingError.keyNotFound`. Swift's
    /// synthesized `Decodable` treats every non-Optional stored property as required unless told
    /// otherwise — this is that "otherwise."
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? RulesLearnedFile.schemaVersion
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        rules = try container.decodeIfPresent([String: String].self, forKey: .rules) ?? [:]
        redactionRules = try container.decodeIfPresent([String: [RedactionRegion]].self, forKey: .redactionRules) ?? [:]
    }

    /// `datetime.now().isoformat(timespec="seconds")` — naive local time, no offset, matching
    /// the real Python writer exactly (and Android's own port of it). Deliberately not
    /// `ISO8601DateFormatter`, which always appends a `Z`/offset — the on-disk format has none.
    static func nowIsoSeconds() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
