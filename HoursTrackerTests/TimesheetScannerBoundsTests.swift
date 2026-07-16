import XCTest
import UniformTypeIdentifiers
@testable import HoursTracker

final class TimesheetScannerBoundsTests: XCTestCase {
    func testValidateFileSizeRejectsOversizedFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("huge-\(UUID().uuidString).bin")
        let oversized = Data(count: Int(TimesheetScannerManager.maxTextFileBytes) + 1)
        try oversized.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(
            try TimesheetScannerManager.validateFileSize(
                at: url,
                maxBytes: TimesheetScannerManager.maxTextFileBytes
            )
        ) { error in
            XCTAssertEqual(error as? TimesheetScannerError, .fileTooLarge)
        }
    }

    func testValidateFileSizeAcceptsSmallFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("small-\(UUID().uuidString).txt")
        try Data("ok".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNoThrow(
            try TimesheetScannerManager.validateFileSize(
                at: url,
                maxBytes: TimesheetScannerManager.maxTextFileBytes
            )
        )
    }

    func testTextImportTypeDetection() {
        XCTAssertTrue(TimesheetScannerManager.isTextImportType(.plainText))
        XCTAssertTrue(TimesheetScannerManager.isTextImportType(.commaSeparatedText))
        XCTAssertFalse(TimesheetScannerManager.isTextImportType(.pdf))
        XCTAssertFalse(TimesheetScannerManager.isTextImportType(.image))
    }

    func testMaxPDFPagesBoundIsPositive() {
        XCTAssertEqual(TimesheetScannerManager.maxPDFPages, 50)
        XCTAssertEqual(TimesheetScannerManager.maxBinaryFileBytes, 50 * 1024 * 1024)
    }
}

final class ZipWriterBoundsTests: XCTestCase {
    func testTruncatedArchiveDoesNotCrash() {
        let truncated = Data([0x50, 0x4b, 0x03, 0x04, 0x00]) // incomplete local header
        XCTAssertThrowsError(try ZipWriter.data(forEntry: "x", in: truncated))
    }

    func testRoundTripStillWorks() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("t.docx")
        let payload = Data("hello".utf8)
        try ZipWriter.createArchive(
            entries: [.init(path: "word/document.xml", data: payload)],
            outputURL: url
        )
        let read = try ZipWriter.data(forEntry: "word/document.xml", inArchiveAt: url)
        XCTAssertEqual(read, payload)
    }
}
