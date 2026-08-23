import CoreGraphics

/// The three user-selectable archive resolutions from plan §4.1 — 150 / 200 / 300 DPI,
/// defaulting to 200. Quality 0.6 across the board; §4.1 found the ~100 KB/page difference
/// between DPI settings is irrelevant against Gmail's attachment ceiling, so quality is not
/// part of what the user picks.
enum CompressionProfile: Int, CaseIterable, Identifiable {
    case dpi150 = 150
    case dpi200 = 200
    case dpi300 = 300

    var id: Int { rawValue }

    var label: String { "\(rawValue) DPI" }

    var jpegQuality: CGFloat { 0.6 }

    /// Long edge in pixels for a letter page (11 in) at this DPI. 200 DPI → 2200 px, per §4.1.
    var maxLongEdgePixels: CGFloat { CGFloat(rawValue) * 11 }

    static let `default` = CompressionProfile.dpi200
}
