import XCTest
@testable import ReceiptScannerBills

/// Same cases as Android's `CompanyNameNormalizerTest.kt`, checked against the same real
/// `Rules_Learned.json` sample entries — not independently invented expectations. Deliberately
/// kept in lockstep with the Kotlin file rather than just "similarly thorough," per plan §8's
/// cross-platform-drift concern.
final class CompanyNameNormalizerTests: XCTestCase {
    func testTitleCasesASingleLowercaseWord() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("energy"), "Energy")
    }

    func testSpacesBecomeUnderscoresBetweenTitleCasedWords() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("duke energy"), "Duke_Energy")
    }

    func testAllCapsInputIsNotLeftShouting() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("DUKE ENERGY"), "Duke_Energy")
    }

    func testRealSampleEntry_unbrokenLetterRunTitleCasesAsOneWord() {
        // "MetLife" has no space, so Python's str.title() treats it as a single word and
        // lowercases everything after the first letter — not "MetLife" unchanged.
        XCTAssertEqual(CompanyNameNormalizer.normalize("MetLife"), "Metlife")
    }

    func testRealSampleEntry_cityOfWinterGarden() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("City of Winter Garden"), "City_Of_Winter_Garden")
    }

    func testRealSampleEntry_trailingPunctuationIsStrippedNotPreserved() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("newrez."), "Newrez")
    }

    func testAmpersandBecomesAndPerTheRealPythonSource() {
        // "AT&T" -> "ATAndT" after the & substitution, then title-cased as one unbroken word
        // (no space survives) -> "Atandt". Confirmed against the Python source, not assumed.
        XCTAssertEqual(CompanyNameNormalizer.normalize("AT&T"), "Atandt")
    }

    func testLegalSuffixPrecededByCommaAndSpaceIsStripped() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("Acme Plumbing, LLC"), "Acme_Plumbing")
    }

    func testLegalSuffixPrecededByJustASpaceWithTrailingPeriodIsStripped() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("Acme Inc."), "Acme")
    }

    func testLegalSuffixLikeWordWithNoPrecedingCommaOrSpaceIsNotStripped() {
        // stripLegalSuffixes requires [,\s]+ immediately before the suffix — "AcmeLLC" has
        // neither, so it survives and gets title-cased as one unbroken word.
        XCTAssertEqual(CompanyNameNormalizer.normalize("AcmeLLC"), "Acmellc")
    }

    func testWindowsIllegalCharacterIsStrippedBeforeTitleCasing() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("A:B"), "Ab")
    }

    func testRepeatedInternalWhitespaceCollapsesToOneUnderscore() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("Duke   Energy"), "Duke_Energy")
    }

    func testLeadingAndTrailingWhitespaceIsTrimmed() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("  Duke Energy  "), "Duke_Energy")
    }

    func testDigitsArePreservedAndActAsTheirOwnWordBoundary() {
        XCTAssertEqual(CompanyNameNormalizer.normalize("Company 365"), "Company_365")
    }

    func testResultIsTruncatedTo50Characters() {
        let result = CompanyNameNormalizer.normalize(String(repeating: "A", count: 60))
        XCTAssertEqual(result.count, 50)
        XCTAssertTrue(result.hasPrefix("Aa"))
    }
}
