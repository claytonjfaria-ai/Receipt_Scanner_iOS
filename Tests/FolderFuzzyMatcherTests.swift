import XCTest
@testable import ReceiptScannerBills

/// Same cases as Android's `FolderFuzzyMatcherTest.kt`.
final class FolderFuzzyMatcherTests: XCTestCase {
    func testIdenticalStringsScoreAPerfect100() {
        XCTAssertEqual(FolderFuzzyMatcher.indelRatio("Duke_Energy", "Duke_Energy"), 100.0, accuracy: 0.0001)
    }

    func testTwoEmptyStringsScoreAPerfect100RatherThanDividingByZero() {
        XCTAssertEqual(FolderFuzzyMatcher.indelRatio("", ""), 100.0, accuracy: 0.0001)
    }

    func testCompletelyDisjointStringsScore0() {
        XCTAssertEqual(FolderFuzzyMatcher.indelRatio("abc", "xyz"), 0.0, accuracy: 0.0001)
    }

    func testMatchesTheKnownIndelRatioFormulaForATextbookExample() {
        // LCS("Atlanta", "Atlantic") = "Atlant" (length 6). ratio = 200*6/(7+8) = 80.0
        XCTAssertEqual(FolderFuzzyMatcher.indelRatio("Atlanta", "Atlantic"), 80.0, accuracy: 0.0001)
    }

    func testANearDuplicateCompanyNameLandsInTheAutoMatchBand() {
        // LCS = 11 (all of "Duke_Energy"), ratio = 200*11/(11+14) = 88.0
        let score = FolderFuzzyMatcher.indelRatio("Duke_Energy", "Duke_Energy_Co")
        XCTAssertGreaterThanOrEqual(score, FolderFuzzyMatcher.autoMatchThreshold)
    }

    func testAPlausibleButDifferentSuffixLandsInTheNearMissBand() {
        // LCS = 11 (all of "Duke_Energy"), ratio = 200*11/(11+16) = 81.48...
        let score = FolderFuzzyMatcher.indelRatio("Duke_Energy", "Duke_Energy_Corp")
        XCTAssertGreaterThanOrEqual(score, FolderFuzzyMatcher.nearMissFloor)
        XCTAssertLessThan(score, FolderFuzzyMatcher.autoMatchThreshold)
    }

    func testAnUnrelatedCompanyNameLandsBelowTheNearMissFloor() {
        let score = FolderFuzzyMatcher.indelRatio("Duke_Energy", "Verizon")
        XCTAssertLessThan(score, FolderFuzzyMatcher.nearMissFloor)
    }

    func testBestMatchPicksTheHighestScoringFolderAmongSeveral() {
        let best = FolderFuzzyMatcher.bestMatch(
            normalizedCompanyName: "Duke_Energy",
            existingFolders: ["Verizon", "AT_T", "Duke_Energy_Corp"]
        )
        XCTAssertEqual(best?.folderName, "Duke_Energy_Corp")
    }

    func testBestMatchReturnsNilWhenThereAreNoExistingFolders() {
        XCTAssertNil(FolderFuzzyMatcher.bestMatch(normalizedCompanyName: "Duke_Energy", existingFolders: []))
    }

    func testBestMatchKeepsTheFirstFolderOnATiedScore() {
        // Both candidates score identically against "Duke_Energy": each is the full 11-character
        // prefix "duke_energy" plus a same-length 4-letter suffix using letters absent from
        // "duke_energy" itself (q/x — so LCS is exactly 11 for both, and the denominator, 11+16,
        // matches too — ratio = 200*11/27 ≈ 81.48 either way). Kotlin's maxByOrNull keeps the
        // first on a tie; Swift's own max(by:) would keep the *last* — this is the regression
        // test for that specific platform-drift risk (see FolderFuzzyMatcher.swift's bestMatch).
        let best = FolderFuzzyMatcher.bestMatch(
            normalizedCompanyName: "Duke_Energy",
            existingFolders: ["Duke_Energy_Qqqq", "Duke_Energy_Xxxx"]
        )
        XCTAssertEqual(best?.folderName, "Duke_Energy_Qqqq")
    }

    func testClassificationIsAutoMatchAtExactlyThe85Threshold() {
        XCTAssertEqual(FolderMatch(folderName: "x", score: 85.0).classification, .autoMatch)
    }

    func testClassificationIsNearMissAtExactlyThe70Floor() {
        XCTAssertEqual(FolderMatch(folderName: "x", score: 70.0).classification, .nearMiss)
    }

    func testClassificationIsNoMatchJustBelowThe70Floor() {
        XCTAssertEqual(FolderMatch(folderName: "x", score: 69.9).classification, .noMatch)
    }
}
