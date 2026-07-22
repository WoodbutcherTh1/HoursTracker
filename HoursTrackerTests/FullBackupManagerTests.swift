import XCTest
import UniformTypeIdentifiers
@testable import HoursTracker

final class FullBackupManagerTests: XCTestCase {
    private var manager: FullBackupManager!
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FullBackupManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        manager = FullBackupManager(backupsDirectory: directory.appendingPathComponent("backups", isDirectory: true))
        manager.clearContentDirty()
    }

    override func tearDownWithError() throws {
        manager.clearContentDirty()
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        manager = nil
        try super.tearDownWithError()
    }

    func testRoundTripLosslessSessionsAndSettings() throws {
        var settings = TestData.settings()
        settings.workerFullName = "Test Worker"
        settings.workerIDNumber = "123456782"
        settings.workplaceName = "Site A"
        settings.contractorName = "Contractor"
        settings.numberOfChildren = 2
        settings.hasChildren = true

        let sessions = [
            TestData.session(day: 1, inHour: 8, outHour: 17),
            TestData.session(day: 2, inHour: 9, outHour: 18),
            TestData.session(day: 3, outHour: nil)
        ]
        let log = [
            ActivityLogEntry(level: .info, category: "clock", message: "Clocked in", details: "manual")
        ]

        let doc = manager.makeDocument(
            settings: settings,
            sessions: sessions,
            activityLog: log,
            exportedAt: TestData.date(2026, 7, 19, 18, 0),
            appVersion: "1.0 (test)"
        )
        XCTAssertEqual(doc.formatID, FullBackupDocument.formatID)
        XCTAssertEqual(doc.sessionCount, 3)

        let data = try manager.encode(doc)
        let decoded = try manager.decode(from: data)

        XCTAssertEqual(decoded.settings.workerFullName, "Test Worker")
        XCTAssertEqual(decoded.settings.workerIDNumber, "123456782")
        XCTAssertEqual(decoded.settings.workplaceName, "Site A")
        XCTAssertEqual(decoded.settings.contractorName, "Contractor")
        XCTAssertEqual(decoded.settings.numberOfChildren, 2)
        XCTAssertEqual(decoded.sessions.count, 3)
        XCTAssertEqual(Set(decoded.sessions.map(\.id)), Set(sessions.map(\.id)))
        XCTAssertEqual(decoded.activityLog.count, 1)
        XCTAssertEqual(decoded.payslipRecords, [])
    }

    func testRejectsGarbageFile() {
        let data = Data("not-a-backup".utf8)
        XCTAssertThrowsError(try manager.decode(from: data))
    }

    func testAcceptsLegacyFullDataExportJSON() throws {
        var settings = TestData.settings()
        settings.workerFullName = "Legacy"
        let exporter = FullDataExportManager()
        let data = try exporter.buildJSON(
            settings: settings,
            sessions: [TestData.session(day: 5)],
            activityLog: [],
            appVersion: "1.0",
            exportedAt: TestData.date(2026, 7, 1)
        )
        let decoded = try manager.decode(from: data)
        XCTAssertEqual(decoded.settings.workerFullName, "Legacy")
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.payslipRecords, [])
    }

    func testDecodeV1JSONWithoutPayslipRecordsDefaultsToEmpty() throws {
        struct V1Document: Codable {
            var formatID: String
            var formatVersion: Int
            var exportedAt: Date
            var appVersion: String
            var settings: WorkplaceSettings
            var sessions: [WorkSession]
            var activityLog: [ActivityLogEntry]
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(
            V1Document(
                formatID: FullBackupDocument.formatID,
                formatVersion: 1,
                exportedAt: TestData.date(2026, 7, 1),
                appVersion: "1.0",
                settings: TestData.settings(),
                sessions: [TestData.session(day: 1)],
                activityLog: []
            )
        )

        let decoded = try manager.decode(from: data)

        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.payslipRecords, [])
    }

    @MainActor
    func testZipBackupRoundTripsPayslipMetadataAndBinary() throws {
        let store = makePayslipStore()
        let id = UUID()
        let bytes = Data("image-bytes".utf8)
        let record = try store.addPayslip(
            fileData: bytes,
            originalFileName: "may-slip.png",
            contentType: .png,
            periodMonth: TestData.date(2026, 5, 21),
            periodStartDay: 1,
            periodLabel: "May 2026",
            extraction: TestData.payslipExtraction(),
            notes: "Needs review",
            id: id,
            uploadedAt: TestData.date(2026, 6, 2, 9)
        )

        let url = try manager.writeExportFile(
            settings: TestData.settings(),
            sessions: [TestData.session(day: 2)],
            activityLog: [],
            exportedAt: TestData.date(2026, 7, 2),
            payslipStore: store
        )
        XCTAssertTrue(url.lastPathComponent.hasSuffix(FullBackupManager.fileExtension))

        store.removeAllStoredData()
        XCTAssertTrue(try store.listPayslips().isEmpty)

        let package = try manager.loadBackupPackage(from: url)
        let appStore = InMemoryStore()
        let viewModel = AppViewModel(
            store: appStore,
            locationManager: MockLocationReminderManager(),
            payslipStore: store,
            fullBackupManager: manager
        )
        try viewModel.restoreBackup(package, mode: .replace)

        let restoredRecords = try store.listPayslips()
        XCTAssertEqual(restoredRecords, [record])
        XCTAssertEqual(try Data(contentsOf: store.url(for: record)), bytes)
        XCTAssertEqual(viewModel.sessions.map(\.id), package.document.sessions.map(\.id))
    }

    func testPreRestoreSnapshotZipContainsPayslipEntries() throws {
        let store = makePayslipStore()
        let id = UUID()
        _ = try store.addPayslip(
            fileData: Data("image-bytes".utf8),
            originalFileName: "may-slip.png",
            contentType: .png,
            periodMonth: TestData.date(2026, 5, 1),
            extraction: TestData.payslipExtraction(),
            id: id
        )

        let url = try manager.writePreRestoreSnapshot(
            settings: TestData.settings(),
            sessions: [],
            activityLog: [],
            at: TestData.date(2026, 7, 3),
            payslipStore: store
        )

        let manifest = try ZipWriter.data(forEntry: "manifest.json", inArchiveAt: url)
        let document = try manager.decode(from: manifest)
        let payslipData = try ZipWriter.data(forEntry: "payslips/\(id.uuidString).png", inArchiveAt: url)
        XCTAssertEqual(document.payslipRecords.map(\.id), [id])
        XCTAssertEqual(payslipData, Data("image-bytes".utf8))
    }

    func testContentDirtyForcesAutomaticBackupWithinInterval() throws {
        let now = TestData.date(2026, 7, 4, 8)
        _ = try manager.performAutomaticBackupIfNeeded(
            settings: TestData.settings(),
            sessions: [],
            activityLog: [],
            force: true,
            now: now,
            payslipStore: makePayslipStore()
        )
        manager.markContentDirty()

        let url = try manager.performAutomaticBackupIfNeeded(
            settings: TestData.settings(),
            sessions: [],
            activityLog: [],
            force: false,
            now: now.addingTimeInterval(60),
            payslipStore: makePayslipStore()
        )

        XCTAssertNotNil(url)
        XCTAssertFalse(manager.isContentDirty())
    }

    @MainActor
    func testOversizedPayslipBinaryInRestorePackageThrows() throws {
        let id = UUID()
        let oversized = Data(count: Int(PayslipStore.maxFileBytes) + 1)
        let document = manager.makeDocument(
            settings: TestData.settings(),
            sessions: [],
            activityLog: [],
            payslipRecords: [TestData.payslipRecord(id: id, fileByteSize: oversized.count)],
            exportedAt: TestData.date(2026, 7, 5)
        )
        let package = FullBackupPackage(document: document, payslipFiles: [id: oversized])
        let viewModel = AppViewModel(
            store: InMemoryStore(),
            locationManager: MockLocationReminderManager(),
            payslipStore: makePayslipStore(),
            fullBackupManager: manager
        )

        XCTAssertThrowsError(
            try viewModel.restoreBackup(package, mode: .merge)
        ) { error in
            guard case let .payslipEntryTooLarge(errorID, bytes) = error as? FullBackupError else {
                return XCTFail("Expected payslipEntryTooLarge, got \(error)")
            }
            XCTAssertEqual(errorID, id)
            XCTAssertEqual(bytes, oversized.count)
        }
    }

    func testSoftMaxBackupBytesConstant() {
        XCTAssertEqual(FullBackupManager.softMaxBackupBytes, 200 * 1024 * 1024)
    }

    private func makePayslipStore() -> PayslipStore {
        PayslipStore(rootDirectory: directory.appendingPathComponent("payslip-store", isDirectory: true))
    }
}
