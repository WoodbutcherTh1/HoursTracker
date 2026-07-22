import XCTest
import UniformTypeIdentifiers
@testable import HoursTracker

@MainActor
final class PayslipUploadViewModelTests: XCTestCase {
    private var directory: URL!
    private var store: PayslipStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PayslipUploadVM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = PayslipStore(rootDirectory: directory)
        BackupContentDirtyFlag.clear()
    }

    override func tearDownWithError() throws {
        BackupContentDirtyFlag.clear()
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        store = nil
        try super.tearDownWithError()
    }

    func testCanSaveRequiresPeriodAndNetOrGross() {
        var draft = PayslipReviewDraft.empty
        XCTAssertFalse(draft.canSave)

        draft.netPay = Decimal(100)
        XCTAssertFalse(draft.canSave)

        draft.paymentMonth = TestData.date(2026, 5, 1)
        XCTAssertTrue(draft.canSave)

        draft.netPay = nil
        draft.grossPay = nil
        XCTAssertFalse(draft.canSave)

        draft.grossPay = Decimal(200)
        XCTAssertTrue(draft.canSave)

        draft.paymentMonth = nil
        draft.payPeriodStart = TestData.date(2026, 5, 1)
        XCTAssertTrue(draft.canSave)
    }

    func testUserOverridesCaptureEditedFieldsOnly() {
        let result = PayslipLLMStructureResult(
            fields: PayslipLLMFields(
                paymentMonth: "2026-05",
                grossPay: 1000,
                netPay: 800,
                currency: "ILS",
                employerName: "Acme",
                employeeName: "Dana",
                confidence: 0.9
            ),
            providerName: "test",
            needsManualReview: false
        )
        var draft = PayslipReviewDraft.from(result: result)
        XCTAssertNil(draft.userOverrides())

        draft.netPay = Decimal(850)
        draft.employerName = "Acme Ltd"
        let overrides = draft.userOverrides()
        XCTAssertEqual(overrides?.netPay, Decimal(850))
        XCTAssertEqual(overrides?.employerName, "Acme Ltd")
        XCTAssertNil(overrides?.grossPay)
        XCTAssertNil(overrides?.employeeName)
    }

    func testCancelDiscardsStagedFileWithoutIndexEntry() throws {
        let staged = try store.stageFile(
            fileData: Data("pdf-bytes".utf8),
            originalFileName: "slip.png",
            contentType: .png
        )
        let url = store.url(forStaged: staged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try store.listPayslips().isEmpty)

        store.discardStaged(staged)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try store.listPayslips().isEmpty)
    }

    func testViewModelCancelAndDiscardRemovesOrphan() async throws {
        let viewModel = PayslipUploadViewModel(store: store)
        let png = minimalPNGData()
        // Stage only path via store, then attach to VM state to test cancel cleanup.
        let staged = try store.stageFile(fileData: png, originalFileName: "t.png", contentType: .png)
        viewModel.staged = staged
        viewModel.phase = .review
        let url = store.url(forStaged: staged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        viewModel.cancelAndDiscard()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(viewModel.staged)
        XCTAssertEqual(viewModel.phase, .pick)
        XCTAssertTrue(try store.listPayslips().isEmpty)
    }

    func testConfirmSavePersistsOverridesAndMarksDirty() throws {
        let staged = try store.stageFile(
            fileData: Data("image-bytes".utf8),
            originalFileName: "slip.png",
            contentType: .png
        )
        var draft = PayslipReviewDraft.from(
            result: PayslipLLMStructureResult(
                fields: PayslipLLMFields(
                    paymentMonth: "2026-06",
                    grossPay: 1200,
                    netPay: 900,
                    currency: "ILS",
                    confidence: 0.4
                ),
                providerName: "local-heuristic",
                needsManualReview: true
            )
        )
        draft.netPay = Decimal(950)
        draft.grossPay = nil // user cleared gross — must not fall back to AI 1200

        BackupContentDirtyFlag.clear()
        let record = try store.commitStaged(
            staged,
            periodMonth: draft.resolvedPeriodMonth,
            extraction: draft.confirmedExtraction(),
            userOverrides: draft.userOverrides(),
            reviewState: .confirmed
        )

        XCTAssertEqual(record.reviewState, .confirmed)
        XCTAssertEqual(record.userOverrides?.netPay, Decimal(950))
        XCTAssertNil(record.userOverrides?.grossPay == nil && draft.grossPay == nil ? nil : record.extraction.grossPay)
        XCTAssertNil(record.extraction.grossPay)
        XCTAssertEqual(record.extraction.netPay, Decimal(950))
        XCTAssertEqual(record.effectiveNetPay, Decimal(950))
        XCTAssertNil(record.effectiveGrossPay)
        XCTAssertFalse(record.extraction.needsManualReview)
        XCTAssertTrue(BackupContentDirtyFlag.isDirty())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: record).path))
    }

    func testCloudToggleOffPassesIncludeCloudFalseAndSkipsCloudProvider() async {
        final class Pref: SmartScannerCloudPreferencing {
            var isEnabled: Bool
            init(_ enabled: Bool) { isEnabled = enabled }
        }
        final class ProbeProvider: PayslipLLMProviding, @unchecked Sendable {
            let name: String
            private(set) var callCount = 0
            init(name: String) { self.name = name }
            func extractPayslip(ocrText: String) async throws -> PayslipLLMStructureResult {
                callCount += 1
                return PayslipLLMStructureResult(
                    fields: PayslipLLMFields(paymentMonth: "2026-01", netPay: 1, confidence: 0.2),
                    providerName: name,
                    needsManualReview: true
                )
            }
        }

        let cloud = ProbeProvider(name: "cloud-probe")
        let local = ProbeProvider(name: "local-probe")
        var includeCloudSeen: Bool?

        let viewModel = PayslipUploadViewModel(
            store: store,
            cloudPreference: Pref(false),
            routerFactory: { includeCloud in
                includeCloudSeen = includeCloud
                var providers: [any PayslipLLMProviding] = []
                if includeCloud { providers.append(cloud) }
                providers.append(local)
                return PayslipLLMRouter(providers: providers)
            }
        )

        await viewModel.processImport(fileData: minimalPNGData(), originalFileName: "t.png", contentType: .png)

        XCTAssertEqual(includeCloudSeen, false)
        XCTAssertEqual(cloud.callCount, 0)
        if case .review = viewModel.phase {
            XCTAssertEqual(local.callCount, 1)
            XCTAssertEqual(viewModel.draft?.extraction.providerName, "local-probe")
        } else if case .failed = viewModel.phase {
            // OCR may fail in Linux CI without Vision — still require cloud was never wired.
            XCTAssertEqual(cloud.callCount, 0)
            XCTAssertEqual(includeCloudSeen, false)
        } else {
            XCTFail("Unexpected phase \(viewModel.phase)")
        }
    }

    func testDefaultRouterExcludesCloudProvidersWhenIncludeCloudFalse() {
        let router = PayslipLLMRouter.default(includeCloud: false, geminiKey: "fake", secondaryKey: "fake")
        // Extract with empty text — local heuristic always runs; cloud providers are not in the chain.
        let expectation = expectation(description: "extract")
        Task {
            let result = await router.extractPayslip(ocrText: "Net pay 100\nMay 2026")
            XCTAssertTrue(result.needsManualReview)
            XCTAssertEqual(result.providerName, "Local")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}

private func minimalPNGData() -> Data {
    let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5W2fQAAAAASUVORK5CYII="
    return Data(base64Encoded: base64)!
}
