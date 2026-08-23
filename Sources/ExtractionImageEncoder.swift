import UIKit

/// Prepares the one page sent to `extract-bill`, independent of the archive's compression
/// (plan §4.2: "Send Gemini the uncompressed page, not the archived one... Send page 1 at
/// capture resolution, or a mild downscale... keep the archive's compression independent of
/// it. If extraction accuracy ever drops after a compression change, look here first.").
///
/// The cap and quality below are a starting point, not a measured target the way the archive's
/// 200 DPI is (main plan's readability test) — there's no equivalent test run yet for
/// extraction specifically. Revisit against the golden set (§7's still-open item) once one
/// exists, the same way the main plan's own model/prompt choices are meant to be tuned.
enum ExtractionImageEncoder {
    /// A raw VisionKit capture can be very large (a modern iPad/iPhone camera easily exceeds
    /// 3000px on the long edge) — this cap keeps the request body reasonable while staying
    /// well above the 200 DPI archive default's ~2200px, so extraction never reads a lower-
    /// resolution image than what gets archived.
    private static let maxLongEdge: CGFloat = 2600
    private static let jpegQuality: CGFloat = 0.85

    static func encode(_ image: UIImage) throws -> (mimeType: String, base64: String) {
        let scaled = PDFBuilder.downscale(image, maxLongEdge: maxLongEdge)
        guard let data = scaled.jpegData(compressionQuality: jpegQuality) else {
            throw PDFBuilderError.encodingFailed
        }
        return ("image/jpeg", data.base64EncodedString())
    }
}
