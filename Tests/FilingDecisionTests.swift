import XCTest
@testable import ReceiptScannerBills

final class FilingDecisionTests: XCTestCase {
    func testRulesCacheHitShortCircuitsFuzzyMatchingEntirely() {
        // A raw OCR string that would never fuzzy-match its resolved folder on its own —
        // this is the whole reason the rules cache exists (see FilingDecision.swift's header).
        let decision = FilingDecision.decide(
            rawCompanyName: "R/O Magic",
            normalizedCompanyName: "R_O_Magic",
            rulesCache: ["R/O Magic": "Quality_First"],
            existingFolders: ["Quality_First"]
        )
        XCTAssertEqual(decision, .fromRulesCache(folderName: "Quality_First"))
        XCTAssertEqual(decision.folderName, "Quality_First")
    }

    func testAutoMatchAboveThreshold() {
        let decision = FilingDecision.decide(
            rawCompanyName: "DUKE ENERGY",
            normalizedCompanyName: "Duke_Energy",
            rulesCache: [:],
            existingFolders: ["Duke_Energy_Co"]
        )
        guard case .autoMatched(let folderName, let score) = decision else {
            return XCTFail("expected .autoMatched, got \(decision)")
        }
        XCTAssertEqual(folderName, "Duke_Energy_Co")
        XCTAssertEqual(score, 88.0, accuracy: 0.01)
        XCTAssertEqual(decision.folderName, "Duke_Energy_Co")
    }

    func testNearMissNeedsConfirmationAndDefaultsToTheExistingFolder() {
        let decision = FilingDecision.decide(
            rawCompanyName: "DUKE ENERGY",
            normalizedCompanyName: "Duke_Energy",
            rulesCache: [:],
            existingFolders: ["Duke_Energy_Corp"]
        )
        guard case .needsConfirmation(let existing, let score, let proposed) = decision else {
            return XCTFail("expected .needsConfirmation, got \(decision)")
        }
        XCTAssertEqual(existing, "Duke_Energy_Corp")
        XCTAssertEqual(proposed, "Duke_Energy")
        XCTAssertGreaterThanOrEqual(score, FolderFuzzyMatcher.nearMissFloor)
        XCTAssertLessThan(score, FolderFuzzyMatcher.autoMatchThreshold)
        // §4.5: the prompt names the existing folder first, and this is the accept-as-is default.
        XCTAssertEqual(decision.folderName, "Duke_Energy_Corp")
    }

    func testNoMatchAndNoExistingFoldersBothProduceANewFolder() {
        XCTAssertEqual(
            FilingDecision.decide(rawCompanyName: "Verizon", normalizedCompanyName: "Verizon", rulesCache: [:], existingFolders: ["Duke_Energy"]),
            .newFolder(folderName: "Verizon")
        )
        XCTAssertEqual(
            FilingDecision.decide(rawCompanyName: "Verizon", normalizedCompanyName: "Verizon", rulesCache: [:], existingFolders: []),
            .newFolder(folderName: "Verizon")
        )
    }

    func testWithRuleLearnedAddsWithoutMutatingTheOriginal() {
        let original: [String: String] = ["A": "Folder_A"]
        let updated = FilingDecision.withRuleLearned(original, rawCompanyName: "B", folderName: "Folder_B")

        XCTAssertEqual(original, ["A": "Folder_A"], "original dictionary must be unchanged")
        XCTAssertEqual(updated, ["A": "Folder_A", "B": "Folder_B"])
    }
}
