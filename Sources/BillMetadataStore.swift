import Foundation

/// The user's confirmed metadata for a staged bill — company/amount/date after Review, plus
/// when it was captured. Persisted as a `.json` sidecar next to the PDF in `BillPdfStore`.
///
/// A stand-in for real Drive filing (plan §4.4), which doesn't exist yet — mirrors Android's
/// own milestone-2-equivalent choice exactly ("Save persists confirmed metadata to a local
/// JSON sidecar (`BillMetadataStore`) as a stand-in for §4.4, which doesn't exist yet"). This
/// is the seam the Drive-filing milestone will read from once it exists.
struct BillMetadata: Codable {
    var companyName: String
    var amount: Double?
    var billingDate: String?
    var capturedAt: Date
}

enum BillMetadataStore {
    private static func sidecarURL(for pdfURL: URL) -> URL {
        pdfURL.deletingPathExtension().appendingPathExtension("json")
    }

    static func save(_ metadata: BillMetadata, for pdfURL: URL) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: sidecarURL(for: pdfURL), options: .atomic)
    }

    static func load(for pdfURL: URL) -> BillMetadata? {
        guard let data = try? Data(contentsOf: sidecarURL(for: pdfURL)) else { return nil }
        return try? JSONDecoder().decode(BillMetadata.self, from: data)
    }

    /// Called alongside `BillPdfStore.delete` so a discarded or filed bill doesn't leave an
    /// orphaned sidecar behind — best-effort, since a missing sidecar is harmless either way.
    static func delete(for pdfURL: URL) {
        try? FileManager.default.removeItem(at: sidecarURL(for: pdfURL))
    }
}
