import XCTest
@testable import ReceiptScannerBills

/// Same cases as Android's `DriveApiFormattingTest.kt`, minus the mimeType/encodeDefaults
/// regression test — that one is Kotlin-specific (kotlinx.serialization's `encodeDefaults`
/// silently dropping a default-valued field is not a failure mode `JSONEncoder` has, since it
/// always encodes every declared, non-optional property). See `DriveAPI.swift`'s
/// `CreateFolderRequestDto` comment for why `mimeType` stays required there regardless.
final class DriveAPIFormattingTests: XCTestCase {
    func testEscapeForDriveQueryLeavesAnOrdinaryNameUnchanged() {
        XCTAssertEqual(escapeForDriveQuery("Duke_Energy"), "Duke_Energy")
    }

    func testEscapeForDriveQueryEscapesASingleQuote() {
        XCTAssertEqual(escapeForDriveQuery("Trader's Joe"), "Trader\\'s Joe")
    }

    func testEscapeForDriveQueryEscapesABackslash() {
        XCTAssertEqual(escapeForDriveQuery("a\\b"), "a\\\\b")
    }

    func testEscapeForDriveQueryEscapesBackslashBeforeQuoteNotTheOtherWayAround() {
        // If a literal backslash were escaped *after* the quote-escaping step instead of
        // before, the quote's own escaping backslash would itself get doubled -- order matters.
        XCTAssertEqual(escapeForDriveQuery("\\'"), "\\\\\\'")
    }

    func testBuildMultipartRelatedBodyProducesTheExactRFC2387ShapeDrivesUploadEndpointExpects() {
        let content = Data([0x25, 0x50, 0x44, 0x46]) // "%PDF"
        let body = buildMultipartRelatedBody(
            boundary: "BOUNDARY",
            metadataJSON: #"{"name":"Duke_Energy_20260812.pdf"}"#,
            mimeType: "application/pdf",
            content: content
        )

        var expected = Data()
        expected.append("--BOUNDARY\r\n".data(using: .utf8)!)
        expected.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        expected.append(#"{"name":"Duke_Energy_20260812.pdf"}"#.data(using: .utf8)!)
        expected.append("\r\n--BOUNDARY\r\n".data(using: .utf8)!)
        expected.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        expected.append(content)
        expected.append("\r\n--BOUNDARY--".data(using: .utf8)!)

        XCTAssertEqual(body, expected)
    }

    func testBuildMultipartRelatedBodyKeepsBinaryContentUntouched() {
        // A real regression risk: routing the file bytes through a String anywhere in the
        // body-building path would corrupt a real PDF's binary content. Bytes outside valid
        // UTF-8 sequences must survive byte-for-byte.
        let binaryContent = Data([0xFF, 0x00, 0x80, 0x7F])
        let body = buildMultipartRelatedBody(boundary: "B", metadataJSON: "{}", mimeType: "application/pdf", content: binaryContent)

        let footerLength = "\r\n--B--".utf8.count
        let extractedRange = (body.count - footerLength - binaryContent.count)..<(body.count - footerLength)
        XCTAssertEqual(Data(body[extractedRange]), binaryContent)
    }
}
