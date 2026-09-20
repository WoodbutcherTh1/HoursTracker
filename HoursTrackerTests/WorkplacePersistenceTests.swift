import XCTest
@testable import HoursTracker

final class WorkplacePersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkplacePersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    func testLoadWorkplacesReturnsEmptyWhenFileMissing() {
        let store = PersistenceManager(fileWriter: RecordingFileWriter(), documentsDirectory: directory)
        XCTAssertEqual(store.loadWorkplaces(), [])
    }

    func testSaveThenLoadRoundTripsWorkplaces() throws {
        let store = PersistenceManager(fileWriter: RecordingFileWriter(), documentsDirectory: directory)
        // Whole-second timestamps: JSONEncoder's `.iso8601` strategy drops fractional
        // seconds, so a `Date()` default here would fail equality after the round trip.
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let workplaces = [
            Workplace(name: "Warehouse", hourlyRate: 45, currencyCode: "ILS", modifiedAt: modifiedAt),
            Workplace(name: "Cafe", hourlyRate: 38, currencyCode: "ILS", modifiedAt: modifiedAt)
        ]

        try store.saveWorkplaces(workplaces)

        XCTAssertEqual(store.loadWorkplaces(), workplaces)
    }

    func testLoadWorkplacesResultDistinguishesMissingFromLoaded() throws {
        let store = PersistenceManager(fileWriter: RecordingFileWriter(), documentsDirectory: directory)
        guard case .missing = store.loadWorkplacesResult() else {
            return XCTFail("Expected .missing before any save")
        }

        try store.saveWorkplaces([
            Workplace(name: "Warehouse", hourlyRate: 45, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        ])
        guard case .loaded(let workplaces) = store.loadWorkplacesResult() else {
            return XCTFail("Expected .loaded after a successful save")
        }
        XCTAssertEqual(workplaces.map(\.name), ["Warehouse"])
    }
}
