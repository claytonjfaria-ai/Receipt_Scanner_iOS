import UIKit

/// A port of Android `Receipt_Scanner`'s `PdfRedactor.kt` — PLAN-MOBILE-BILLS-CAPTURE.md §4.7:
/// "an opaque, drawn-in rectangle that overwrites the underlying pixels ... The output file must
/// not contain the original pixels in any form." Every page is re-rendered and rewritten, not
/// just the redacted ones — there's no way to copy an existing PDF page's content across
/// untouched while also drawing fresh content onto other pages of the same document, the same
/// limitation Android's version hits with `PdfDocument`.
///
/// **Reuses `PDFBuilder.makePDF` for the actual reassembly, rather than duplicating its
/// downscale/JPEG/CGImage-embedding logic here.** This is genuinely "render each page to a
/// `UIImage`, draw a redaction box on some of them, then run the exact same page-array-to-PDF
/// pipeline Review already trusts for every other bill" — simpler than Android's version, which
/// had to hand-roll a second `PdfDocument`-writing path because it never assembles from an image
/// array in the first place (§4.1: iOS does, since VisionKit hands back pages, not a finished PDF).
enum PdfRedactor {
    /// Renders `sourcePDF` at `profile`'s own DPI (the file that actually ships to Drive, not the
    /// lower-fidelity preview DPI `BillPageRenderer`'s editor preview uses), draws every region
    /// opaque-black onto its page, and reassembles a brand-new PDF via `PDFBuilder`. The result is
    /// a fresh file in `BillPdfStore`'s staging directory — the caller is responsible for deleting
    /// it once its bytes have been read for upload.
    static func redact(sourcePDF: URL, regions: [RedactionRegion], profile: CompressionProfile) throws -> URL {
        let pageCount = try BillPageRenderer.pageCount(of: sourcePDF)
        let regionsByPage = Dictionary(grouping: regions, by: \.page)

        var redactedPages: [UIImage] = []
        redactedPages.reserveCapacity(pageCount)
        for index in 0..<pageCount {
            let page = try BillPageRenderer.renderPage(of: sourcePDF, page: index, dpi: CGFloat(profile.rawValue))
            let regionsOnPage = regionsByPage[index] ?? []
            redactedPages.append(regionsOnPage.isEmpty ? page : drawRedactions(regionsOnPage, on: page))
        }

        return try PDFBuilder.makePDF(from: redactedPages, fileName: "redacted_\(UUID().uuidString).pdf", profile: profile)
    }

    /// Opaque fill, not a semi-transparent overlay — a viewer must not be able to see or recover
    /// what was underneath.
    private static func drawRedactions(_ regions: [RedactionRegion], on image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            UIColor.black.setFill()
            for region in regions {
                let rect = region.rect
                context.fill(CGRect(
                    x: rect.x * image.size.width,
                    y: rect.y * image.size.height,
                    width: rect.width * image.size.width,
                    height: rect.height * image.size.height
                ))
            }
        }
    }
}
