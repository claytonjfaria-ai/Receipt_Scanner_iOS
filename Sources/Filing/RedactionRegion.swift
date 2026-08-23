import Foundation

/// A port of Android `Receipt_Scanner`'s `RedactionRegion.kt` model — not because §4.7
/// (PII redaction) is being built on iOS yet, but because `RulesLearnedFile` needs to round-trip
/// this shape correctly. If iOS decoded `redaction_rules` into nothing and re-encoded the file,
/// it would silently delete any redaction rules Android already wrote — the same class of
/// silent-data-loss bug the `encodeDefaults` trap in this project's history is (see
/// `RulesLearnedFile.swift`). Modeling the real shape now, even unused, is what avoids that.
///
/// Plan §4.7: "recorded as a normalized rectangle (fraction of page width/height, 0.0–1.0) ...
/// because the DPI picker means captured page dimensions vary by setting."
struct NormalizedRect: Codable, Equatable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// One redaction box tied to a specific page of the archived PDF. `page` is 0-based.
///
/// `Hashable`, not just `Equatable`: §4.7's redaction editor (`RedactionEditorView`) needs it for
/// `ForEach(regionsOnPage, id: \.self)` over the boxes drawn on one page.
struct RedactionRegion: Codable, Equatable, Hashable {
    let page: Int
    let rect: NormalizedRect
}
