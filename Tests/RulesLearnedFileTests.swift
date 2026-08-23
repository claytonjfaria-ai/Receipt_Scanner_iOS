import XCTest
@testable import ReceiptScannerBills

final class RulesLearnedFileTests: XCTestCase {
    func testDecodesTheRealOnDiskShape() throws {
        let json = """
        {"version": "1.0", "updated_at": "2026-05-22T23:38:59", "rules": {"DUKE ENERGY": "Duke_Energy"}}
        """
        let file = try JSONDecoder().decode(RulesLearnedFile.self, from: Data(json.utf8))

        XCTAssertEqual(file.version, "1.0")
        XCTAssertEqual(file.updatedAt, "2026-05-22T23:38:59")
        XCTAssertEqual(file.rules, ["DUKE ENERGY": "Duke_Energy"])
        XCTAssertEqual(file.redactionRules, [:], "a file predating §4.7 must decode redaction_rules as empty, not throw")
    }

    func testDecodesAFileThatAlreadyHasRedactionRules() throws {
        let json = """
        {
          "version": "1.0", "updated_at": "2026-08-22T10:00:00",
          "rules": {"Citi": "Citi"},
          "redaction_rules": {"Citi": [{"page": 0, "rect": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.05}}]}
        }
        """
        let file = try JSONDecoder().decode(RulesLearnedFile.self, from: Data(json.utf8))

        XCTAssertEqual(file.redactionRules["Citi"]?.first?.page, 0)
        XCTAssertEqual(file.redactionRules["Citi"]?.first?.rect.x, 0.1, accuracy: 0.0001)
    }

    /// The whole reason `redactionRules` is modeled at all on iOS before §4.7 is built here —
    /// without it, this exact round trip would silently delete Android's redaction rules.
    func testRoundTripPreservesRedactionRulesEvenThoughIOSNeverWritesToThemYet() throws {
        let json = """
        {"version": "1.0", "updated_at": "2026-08-22T10:00:00", "rules": {}, \
        "redaction_rules": {"Citi": [{"page": 0, "rect": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.05}}]}}
        """
        var file = try JSONDecoder().decode(RulesLearnedFile.self, from: Data(json.utf8))
        // Simulate iOS learning an unrelated folder rule and writing the file back.
        file.rules = FilingDecision.withRuleLearned(file.rules, rawCompanyName: "Duke Energy", folderName: "Duke_Energy")

        let reEncoded = try JSONDecoder().decode(RulesLearnedFile.self, from: JSONEncoder().encode(file))

        XCTAssertEqual(reEncoded.rules, ["Duke Energy": "Duke_Energy"])
        XCTAssertEqual(reEncoded.redactionRules["Citi"]?.first?.page, 0, "redaction_rules must survive a write this app never intended to touch")
    }

    func testMissingUpdatedAtStillThrowsRatherThanSilentlyDefaulting() {
        // updated_at has no sensible default (unlike version/rules/redaction_rules) — a file
        // missing it entirely is malformed, and should fail loudly, not decode to "".
        let json = #"{"version": "1.0", "rules": {}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(RulesLearnedFile.self, from: Data(json.utf8)))
    }
}
