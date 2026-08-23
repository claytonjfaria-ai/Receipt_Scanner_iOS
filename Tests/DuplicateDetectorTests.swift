import XCTest
@testable import ReceiptScannerBills

final class DuplicateDetectorTests: XCTestCase {
    func testFindsAnExactCompanyAndDateMatch() {
        let candidate = FiledDocumentKey(normalizedCompanyName: "Duke_Energy", filingDate: SimpleDate(year: 2026, month: 8, day: 12))
        let existing = [
            FiledDocumentKey(normalizedCompanyName: "Verizon", filingDate: SimpleDate(year: 2026, month: 8, day: 1)),
            candidate,
        ]
        XCTAssertEqual(DuplicateDetector.findProbableDuplicate(candidate: candidate, existingInTargetFolder: existing), candidate)
    }

    func testSameCompanyDifferentDateIsNotAMatch() {
        let candidate = FiledDocumentKey(normalizedCompanyName: "Duke_Energy", filingDate: SimpleDate(year: 2026, month: 8, day: 12))
        let existing = [FiledDocumentKey(normalizedCompanyName: "Duke_Energy", filingDate: SimpleDate(year: 2026, month: 9, day: 12))]
        XCTAssertNil(DuplicateDetector.findProbableDuplicate(candidate: candidate, existingInTargetFolder: existing))
    }

    func testEmptyTargetFolderNeverMatches() {
        let candidate = FiledDocumentKey(normalizedCompanyName: "Duke_Energy", filingDate: SimpleDate(year: 2026, month: 8, day: 12))
        XCTAssertNil(DuplicateDetector.findProbableDuplicate(candidate: candidate, existingInTargetFolder: []))
    }
}
