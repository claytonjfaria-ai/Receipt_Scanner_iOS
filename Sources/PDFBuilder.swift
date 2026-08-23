import UIKit

enum PDFBuilderError: LocalizedError {
    case noPages
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noPages: return "There are no scanned pages to assemble."
        case .encodingFailed: return "A page could not be JPEG-encoded."
        }
    }
}

/// Assembles captured pages into a single multi-page PDF, entirely on-device, at the
/// archive resolution set in `BillCapturePreferences` (plan §4.1).
///
/// Android gets this free via ML Kit's `RESULT_FORMAT_PDF`. VisionKit hands back `UIImage`
/// pages instead, so iOS has to do the assembly step itself — including the compression ML
/// Kit applies for free. The compression approach here (downscale, JPEG-encode, draw as a
/// JPEG-backed `CGImage`) was worked out and measured in BillsCaptureTest (dev/iOs_Test):
/// the naive path (draw a plain `UIImage`) produced 6.6 MB for a two-page bill because
/// CoreGraphics decodes and re-embeds it losslessly regardless of any prior JPEG encoding.
enum PDFBuilder {
    static func makePDF(
        from images: [UIImage],
        fileName: String,
        profile: CompressionProfile = BillCapturePreferences.resolution
    ) throws -> URL {
        guard !images.isEmpty else { throw PDFBuilderError.noPages }

        let url = try BillPdfStore.stagingURL(fileName: fileName)
        // Placeholder bounds only — each page overrides it with the page's own size.
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))

        // `writePDF`'s closure cannot throw, so a page failure is captured and rethrown after
        // the fact rather than swallowed — a half-assembled PDF must not be mistaken for a
        // good one.
        var pageError: Error?

        try renderer.writePDF(to: url) { context in
            for image in images where pageError == nil {
                // A page's downscaled copy and JPEG buffer are transients; without this pool,
                // every intermediate bitmap for the whole document is held at once until the
                // run loop gets a turn — real cost on a 30-page ATIC-sized document (plan §4.1).
                autoreleasepool {
                    do {
                        try drawCompressedPage(image, dpi: CGFloat(profile.rawValue), quality: profile.jpegQuality, into: context)
                    } catch {
                        pageError = error
                    }
                }
            }
        }

        if let pageError {
            try? FileManager.default.removeItem(at: url)
            throw pageError
        }

        return url
    }

    // MARK: - Page drawing

    /// Downscales, JPEG-encodes, then draws a **JPEG-backed** `CGImage`.
    ///
    /// The JPEG backing is the whole trick: CoreGraphics passes DCT-encoded image data
    /// through into the PDF untouched. Drawing a plain `UIImage` — even one that was just
    /// JPEG-encoded — decodes it back to a bitmap first and re-embeds it losslessly, which is
    /// why a naive draw call produces a multi-megabyte page despite VisionKit's source image
    /// looking compressed.
    private static func drawCompressedPage(
        _ image: UIImage,
        dpi: CGFloat,
        quality: CGFloat,
        into context: UIGraphicsPDFRendererContext
    ) throws {
        let scaled = downscale(image, maxLongEdge: dpi * 11)

        guard
            let data = scaled.jpegData(compressionQuality: quality),
            let provider = CGDataProvider(data: data as CFData),
            let cgImage = CGImage(
                jpegDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else { throw PDFBuilderError.encodingFailed }

        // Page size in PDF points: pixels ÷ DPI × 72. Letter at 200 DPI lands at 612 × 792.
        let pageRect = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(cgImage.width) / dpi * 72,
            height: CGFloat(cgImage.height) / dpi * 72
        )

        context.beginPage(withBounds: pageRect, pageInfo: [:])

        // UIGraphicsPDFRenderer flips the CTM for UIKit drawing; CoreGraphics draws bottom-up,
        // so flip back for this one draw call or the page renders upside down.
        let cg = context.cgContext
        cg.saveGState()
        cg.translateBy(x: 0, y: pageRect.height)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(cgImage, in: CGRect(origin: .zero, size: pageRect.size))
        cg.restoreGState()
    }

    private static func downscale(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longEdge = max(pixelSize.width, pixelSize.height)

        guard longEdge > maxLongEdge else {
            // Small enough already — but the caller JPEG-encodes this and rebuilds it through
            // `CGImage(jpegDataProviderSource:)`, which ignores the EXIF orientation tag
            // `jpegData` writes. Redraw anything non-`.up` so the pixels themselves are
            // upright. VisionKit pages arrive `.up`, so this only matters if pages ever come
            // from elsewhere.
            return image.imageOrientation == .up ? image : redraw(image, at: pixelSize)
        }

        let factor = maxLongEdge / longEdge
        return redraw(image, at: CGSize(width: pixelSize.width * factor, height: pixelSize.height * factor))
    }

    /// Draws `image` into a fresh bitmap of `size`, which also bakes `imageOrientation` into
    /// the pixels — `UIImage.draw` applies the orientation, so what comes back is always `.up`.
    private static func redraw(_ image: UIImage, at size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1        // size is already in pixels
        format.opaque = true    // JPEG has no alpha channel to preserve

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - File size

    static func byteCount(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func fileSizeDescription(of url: URL) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount(of: url)), countStyle: .file)
    }
}
