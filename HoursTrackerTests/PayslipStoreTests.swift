import XCTest
import UniformTypeIdentifiers
@testable import HoursTracker

final class PayslipStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PayslipStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    func testCreateListAndDeletePayslip() throws {
        let store = makeStore()
        let id = UUID()
        let periodMonth = TestData.date(2026, 5, 21)

        let record = try store.addPayslip(
            fileData: Data("image-bytes".utf8),
            originalFileName: "may-slip.png",
            contentType: .png,
            periodMonth: periodMonth,
            periodStartDay: 1,
            periodLabel: "May 2026",
            extraction: makeExtraction(),
            notes: "Needs review",
            id: id,
            uploadedAt: TestData.date(2026, 6, 2, 9)
        )

        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.sourceKind, .image)
        XCTAssertEqual(record.reviewState, .pendingReview)
        XCTAssertEqual(record.originalFileName, "may-slip.png")
        XCTAssertEqual(record.relativeFilePath, "payslips/files/\(id.uuidString).png")
        XCTAssertEqual(record.fileByteSize, Data("image-bytes".utf8).count)
        XCTAssertEqual(record.contentTypeUTI, UTType.png.identifier)
        XCTAssertEqual(record.periodMonth, TestData.date(2026, 5, 1))
        XCTAssertEqual(record.effectiveNetPay, Decimal(1010.50))
        XCTAssertEqual(record.effectiveGrossPay, Decimal(1250))
        XCTAssertEqual(record.effectivePeriodMonth, TestData.date(2026, 5, 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: record).path))

        let listed = try store.listPayslips()
        XCTAssertEqual(listed, [record])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.indexURL.path))

        try store.deletePayslip(id: id)

        XCTAssertTrue(try store.listPayslips().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: record).path))
    }

    func testOversizedFileIsRejectedBeforeWriting() {
        let writer = RecordingFileWriter()
        let store = makeStore(fileWriter: writer)
        let data = Data(count: Int(PayslipStore.maxFileBytes) + 1)

        XCTAssertThrowsError(
            try store.addPayslip(
                fileData: data,
                originalFileName: "huge.png",
                contentType: .png,
                periodMonth: TestData.date(2026, 5, 1),
                extraction: makeExtraction()
            )
        ) { error in
            guard case let .fileTooLarge(maxBytes, actualBytes) = error as? PayslipStoreError else {
                return XCTFail("Expected fileTooLarge, got \(error)")
            }
            XCTAssertEqual(maxBytes, PayslipStore.maxFileBytes)
            XCTAssertEqual(actualBytes, Int64(data.count))
        }

        XCTAssertTrue(writer.urls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.indexURL.path))
    }

    func testPasswordProtectedPDFIsRejectedBeforeWriting() {
        let writer = RecordingFileWriter()
        let store = makeStore(
            fileWriter: writer,
            pdfInspector: StubPDFInspector(result: .locked)
        )

        XCTAssertThrowsError(
            try store.addPayslip(
                fileData: Data("%PDF-locked".utf8),
                originalFileName: "locked.pdf",
                contentType: .pdf,
                periodMonth: TestData.date(2026, 5, 1),
                extraction: makeExtraction()
            )
        ) { error in
            XCTAssertEqual(error as? PayslipStoreError, .passwordProtectedPDF)
        }

        XCTAssertTrue(writer.urls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.indexURL.path))
    }

    func testTransientReadFailureDoesNotReplaceExistingIndex() throws {
        let store = makeStore()
        let existingID = UUID()
        _ = try store.addPayslip(
            fileData: Data("existing-image".utf8),
            originalFileName: "existing.png",
            contentType: .png,
            periodMonth: TestData.date(2026, 5, 1),
            extraction: makeExtraction(),
            id: existingID
        )
        let originalIndexData = try Data(contentsOf: store.indexURL)

        let transientError = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let writer = RecordingFileWriter()
        let unavailableStore = makeStore(
            fileWriter: writer,
            dataReader: FailingDataReader(error: transientError)
        )

        XCTAssertThrowsError(try unavailableStore.listPayslips()) { error in
            XCTAssertEqual(error as? PayslipStoreError, .temporarilyUnavailable)
        }

        let newID = UUID()
        XCTAssertThrowsError(
            try unavailableStore.addPayslip(
                fileData: Data("new-image".utf8),
                originalFileName: "new.png",
                contentType: .png,
                periodMonth: TestData.date(2026, 6, 1),
                extraction: makeExtraction(),
                id: newID
            )
        ) { error in
            XCTAssertEqual(error as? PayslipStoreError, .temporarilyUnavailable)
        }

        XCTAssertEqual(try Data(contentsOf: store.indexURL), originalIndexData)
        XCTAssertTrue(writer.urls.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("payslips/files/\(newID.uuidString).png")
                    .path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.indexURL.path))
    }

    func testStageAndDiscardLeavesNoOrphanOrIndexEntry() throws {
        let store = makeStore()
        let staged = try store.stageFile(
            fileData: Data("bytes".utf8),
            originalFileName: "a.png",
            contentType: .png
        )
        let url = store.url(forStaged: staged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try store.listPayslips().isEmpty)

        store.discardStaged(staged)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try store.listPayslips().isEmpty)
    }

    private func makeStore(
        fileWriter: FileWriting = ProtectedFileWriter.shared,
        dataReader: DataReading = DefaultDataReader.shared,
        pdfInspector: PayslipPDFInspecting = StubPDFInspector(result: .unlocked)
    ) -> PayslipStore {
        PayslipStore(
            fileWriter: fileWriter,
            dataReader: dataReader,
            pdfInspector: pdfInspector,
            rootDirectory: directory
        )
    }

    private func makeExtraction() -> PayslipExtraction {
        PayslipExtraction(
            providerName: "UnitTestOCR",
            extractedAt: TestData.date(2026, 6, 1, 10),
            confidence: 0.92,
            needsManualReview: false,
            rawJSON: #"{"net":1010.50}"#,
            grossPay: Decimal(1250),
            netPay: Decimal(1010.50),
            currencyCode: "ILS",
            employerName: "Example Employer",
            employeeName: "Example Worker",
            employeeID: "123456789",
            payPeriodStart: TestData.date(2026, 5, 1),
            payPeriodEnd: TestData.date(2026, 5, 31),
            paymentDate: TestData.date(2026, 6, 1),
            hoursRegular: 160,
            hoursOT: 8,
            deductionsTotal: Decimal(120),
            extras: ["department": "QA"]
        )
    }
}

private struct StubPDFInspector: PayslipPDFInspecting {
    let result: PayslipPDFInspectionResult

    func inspectPDF(at url: URL) -> PayslipPDFInspectionResult {
        result
    }

    func inspectPDF(data: Data) -> PayslipPDFInspectionResult {
        result
    }
}

private struct FailingDataReader: DataReading {
    let error: Error

    func read(from url: URL) throws -> Data {
        throw error
    }
}
