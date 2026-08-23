import PDFKit
import UIKit

enum BillPageRendererError: LocalizedError {
    case pageOutOfRange
    case unopenable

    var errorDescription: String? {
        switch self {
        case .pageOutOfRange: return "That page doesn't exist in this bill."
        case .unopenable: return "Couldn't open the saved bill."
        }
    }
}

/// Renders pages of the already-saved archive PDF back to `UIImage`s for §4.7's redaction
/// editor — iOS's counterpart to Android `Receipt_Scanner`'s `BillPageRenderer.renderPageBitmap`
/// (`android.graphics.pdf.PdfRenderer`-based). Uses PDFKit, a system framework — no extra
/// dependency, same reasoning as Android reaching for the platform's own PDF renderer rather than
/// a bundled library.
enum BillPageRenderer {
    /// Preview quality only — good enough to place a redaction box accurately by eye.
    /// `PdfRedactor` always re-renders the actual output at the archive's own DPI setting, not
    /// this one, matching Android's same `REDACTION_PREVIEW_DPI` vs. archive-DPI split.
    static let previewDPI: CGFloat = 150
    private static let pointsPerInch: CGFloat = 72

    static func pageCount(of pdfURL: URL) throws -> Int {
        guard let document = PDFDocument(url: pdfURL) else { throw BillPageRendererError.unopenable }
        return document.pageCount
    }

    static func renderPage(of pdfURL: URL, page index: Int, dpi: CGFloat) throws -> UIImage {
        guard let document = PDFDocument(url: pdfURL) else { throw BillPageRendererError.unopenable }
        guard index >= 0, index < document.pageCount, let page = document.page(at: index) else {
            throw BillPageRendererError.pageOutOfRange
        }
        return render(page, dpi: dpi)
    }

    /// `PDFPage.draw(with:to:)` draws in PDF's native bottom-up coordinate system — the
    /// translate+flip below is the standard, documented way to make that render right-side up
    /// into a `UIGraphicsImageRenderer` context, the same shape of fix `PDFBuilder`'s own
    /// `drawCompressedPage` already needed for its CGImage draw call.
    private static func render(_ page: PDFPage, dpi: CGFloat) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / pointsPerInch
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // size is already in the target pixel dimensions
        format.opaque = true // matches a scanned page: no transparency to preserve

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }
    }
}
