import Foundation

enum BillPdfStoreError: LocalizedError {
    case directoryUnavailable

    var errorDescription: String? {
        "Could not access on-device storage for staged bills."
    }
}

/// Where a captured bill's assembled PDF lives before it's filed to Drive.
///
/// Deliberately **not** the temporary directory: `NSTemporaryDirectory` can be purged by the
/// OS at any time, and a bill the user has just captured is real, unsaved work. Android's
/// equivalent is `BillPdfFileStore` (`files/bills/<billId>/`), which plan §4.6 Tier 3 and its
/// "1 bill not yet filed" indicator are built on — this is the iOS foundation for the same
/// idea, though the full three-tier reliability design (§4.6) isn't wired up yet at this
/// milestone (capture-only).
enum BillPdfStore {
    private static var stagingDirectory: URL {
        get throws {
            guard
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { throw BillPdfStoreError.directoryUnavailable }
            let dir = documents.appendingPathComponent("StagedBills", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }

    /// A fresh, durable destination for a newly assembled PDF. Called by `PDFBuilder`.
    static func stagingURL(fileName: String) throws -> URL {
        try stagingDirectory.appendingPathComponent(fileName)
    }

    /// Every PDF currently staged (captured but not yet filed) — the on-disk fact the future
    /// "not yet filed" indicator (§4.6 Tier 3) will read from, the same way Android's
    /// `stagedBillIds()` reads what's actually on disk rather than tracking in-memory state.
    static func stagedPDFs() -> [URL] {
        guard let dir = try? stagingDirectory else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
    }

    /// Discards a staged bill — used once a capture is filed, or the user discards it outright
    /// (mirrors Android's `onDiscardConfirmed`, plan §4.4). Throws rather than silently
    /// swallowing a failed delete — the exact `deleteRecursively` silent-failure bug hit on
    /// Android (returns `false` instead of throwing) is the thing to avoid repeating here.
    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
