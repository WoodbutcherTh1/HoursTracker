import XCTest
import UniformTypeIdentifiers
@testable import HoursTracker

final class PayslipLibraryTests: XCTestCase {
    private var directory: URL!
    private var thumbDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PayslipLibrary-\(UUID().uuidString)", isDirectory: true)
        thumbDirectory = directory.appendingPathComponent("thumbs", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        thumbDirectory = nil
        try super.tearDownWithError()
    }

    func testThumbnailCacheDirectoryIsNotInsideAppGroupPayslipsPath() {
        let cache = PayslipThumbnailCache(cacheDirectory: thumbDirectory)
        let path = cache.directoryURL.path

        XCTAssertTrue(path.contains("thumbs") || path.contains("Caches") || path.contains("PayslipThumbnails") || path.hasPrefix(thumbDirectory.path))
        XCTAssertFalse(path.contains("/payslips/files"))
        XCTAssertFalse(path.contains(PayslipStore.appGroupIdentifier))
        // Backup packages only `payslips/` under the store root — thumbs must stay outside that tree.
        XCTAssertFalse(path.hasSuffix("/payslips"))
        XCTAssertFalse(path.contains("/payslips/"))
    }

    func testDefaultThumbnailCacheUsesCachesDirectory() {
        let cache = PayslipThumbnailCache.shared
        let path = cache.directoryURL.path
        XCTAssertTrue(path.contains("Caches") || path.contains("PayslipThumbnails"))
        XCTAssertFalse(path.contains("/payslips/files"))
        XCTAssertFalse(path.contains("group.com.hourstracker.app"))
    }

    func testGridSortsByPeriodMonthDescending() {
        // `effectivePeriodMonth` prefers `extraction.payPeriodStart` over `periodMonth`;
        // clear it so each record's own `periodMonth` actually drives the sort.
        var older = TestData.payslipRecord(
            id: UUID(),
            periodMonth: TestData.date(2026, 3, 1),
            uploadedAt: TestData.date(2026, 7, 1)
        )
        older.extraction.payPeriodStart = nil
        var newer = TestData.payslipRecord(
            id: UUID(),
            periodMonth: TestData.date(2026, 6, 1),
            uploadedAt: TestData.date(2026, 7, 2)
        )
        newer.extraction.payPeriodStart = nil
        var mid = TestData.payslipRecord(
            id: UUID(),
            periodMonth: TestData.date(2026, 5, 1),
            uploadedAt: TestData.date(2026, 7, 3)
        )
        mid.extraction.payPeriodStart = nil

        let sorted = PayslipLibraryViewModel.sortedByPeriodDescending([older, newer, mid])
        XCTAssertEqual(sorted.map(\.id), [newer.id, mid.id, older.id])
    }

    func testDeleteRemovesBinaryAndCachedThumbnail() throws {
        let store = PayslipStore(rootDirectory: directory.appendingPathComponent("store", isDirectory: true))
        let cache = PayslipThumbnailCache(cacheDirectory: thumbDirectory)
        let id = UUID()
        let record = try store.addPayslip(
            fileData: Data("image-bytes".utf8),
            originalFileName: "slip.png",
            contentType: .png,
            periodMonth: TestData.date(2026, 5, 1),
            extraction: TestData.payslipExtraction(),
            id: id
        )

        let thumbURL = cache.fileURL(for: id)
        try Data("thumb".utf8).write(to: thumbURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: record).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path))

        // Production delete clears the shared cache; exercise the same cleanup API.
        try store.deletePayslip(id: id)
        cache.remove(id: id)

        XCTAssertTrue(try store.listPayslips().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: record).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbURL.path))
    }

    func testImageThumbnailRendererProducesBitmap() throws {
        let pngURL = directory.appendingPathComponent("one.png")
        try minimalPNGData().write(to: pngURL)
        let image = PayslipThumbnailCache.renderImageThumbnail(at: pngURL, pixelSize: 64)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image!.size.width, 0)
        XCTAssertGreaterThan(image!.size.height, 0)
    }

    func testStoreDeleteClearsSharedThumbnailCacheEntry() throws {
        let store = PayslipStore(rootDirectory: directory.appendingPathComponent("store2", isDirectory: true))
        let id = UUID()
        _ = try store.addPayslip(
            fileData: Data("bytes".utf8),
            originalFileName: "a.png",
            contentType: .png,
            periodMonth: TestData.date(2026, 4, 1),
            extraction: TestData.payslipExtraction(),
            id: id
        )
        let sharedURL = PayslipThumbnailCache.shared.fileURL(for: id)
        try Data("cached".utf8).write(to: sharedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedURL.path))

        try store.deletePayslip(id: id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedURL.path))
    }
}

private func minimalPNGData() -> Data {
    let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5W2fQAAAAASUVORK5CYII="
    return Data(base64Encoded: base64)!
}
