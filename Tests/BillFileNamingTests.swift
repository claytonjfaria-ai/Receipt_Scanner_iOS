import XCTest
@testable import ReceiptScannerBills

/// Same cases as Android's `BillFileNamingTest.kt`.
final class BillFileNamingTests: XCTestCase {
    private let captureDate = SimpleDate(year: 2026, month: 8, day: 21)

    func testResolveFilingDateUsesTheParsedBillingDateWhenPresent() {
        XCTAssertEqual(
            BillFileNaming.resolveFilingDate(billingDate: "2026-08-12", captureDate: captureDate),
            SimpleDate(year: 2026, month: 8, day: 12)
        )
    }

    func testResolveFilingDateFallsBackToCaptureDateWhenBillingDateIsNil() {
        XCTAssertEqual(BillFileNaming.resolveFilingDate(billingDate: nil, captureDate: captureDate), captureDate)
    }

    func testResolveFilingDateFallsBackToCaptureDateWhenBillingDateIsBlank() {
        XCTAssertEqual(BillFileNaming.resolveFilingDate(billingDate: "   ", captureDate: captureDate), captureDate)
    }

    func testResolveFilingDateFallsBackToCaptureDateOnAnUnparseableValueRatherThanCrashing() {
        XCTAssertEqual(BillFileNaming.resolveFilingDate(billingDate: "not a date", captureDate: captureDate), captureDate)
    }

    func testBuildFilingFileNameMatchesTheCompanyYYYYMMDDConvention() {
        XCTAssertEqual(
            BillFileNaming.buildFilingFileName(folderName: "Duke_Energy", filingDate: SimpleDate(year: 2026, month: 8, day: 12)),
            "Duke_Energy_20260812.pdf"
        )
    }

    func testBuildFilingFolderPathNestsUnderScans() {
        XCTAssertEqual(BillFileNaming.buildFilingFolderPath(folderName: "Duke_Energy"), "Scans/Duke_Energy")
    }
}
