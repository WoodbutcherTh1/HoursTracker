import XCTest
@testable import HoursTracker

/// Multiple workplaces: shifts and pay never mix, storage keeps everything.
@MainActor
final class WorkplaceTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkplaceTests-\(UUID().uuidString)", isDirectory: true)
        AppViewModel.storeActiveWorkplaceID(nil)
        UserDefaults.standard.removeObject(forKey: AppViewModel.showAllWorkplacesKey)
    }

    override func tearDown() {
        AppViewModel.storeActiveWorkplaceID(nil)
        UserDefaults.standard.removeObject(forKey: AppViewModel.showAllWorkplacesKey)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeViewModel(sessions: [WorkSession] = [], rate: Double = 100) -> (AppViewModel, InMemoryStore) {
        let store = InMemoryStore()
        store.storedSessions = sessions
        store.storedSettings = TestData.settings(hourlyRate: rate)
        let viewModel = AppViewModel(
            store: store,
            locationManager: MockLocationReminderManager(),
            deletedSessions: DeletedSessionsStore(directory: directory),
            backups: LocalBackupStore(directory: directory.appendingPathComponent("Backups"))
        )
        return (viewModel, store)
    }

    func testOneWorkplaceBehavesExactlyAsBefore() {
        let shift = TestData.session(day: 5)
        let (viewModel, _) = makeViewModel(sessions: [shift])
        XCTAssertFalse(viewModel.hasMultipleWorkplaces)
        XCTAssertEqual(viewModel.workSessions, viewModel.sessions)
        XCTAssertEqual(viewModel.activeSettings, viewModel.settings)
    }

    func testEachWorkplaceShowsAndPricesOnlyItsOwnShifts() throws {
        let mainShift = TestData.session(day: 5)
        let (viewModel, store) = makeViewModel(sessions: [mainShift], rate: 100)

        let secondID = try XCTUnwrap(viewModel.addWorkplace(named: "Cafe"))
        XCTAssertEqual(viewModel.activeWorkplaceKey, secondID)
        var cafe = viewModel.activeSettings
        cafe.hourlyRate = 50
        viewModel.saveActiveWorkplaceSettings(cafe)

        viewModel.addManualSession(
            date: TestData.date(2026, 1, 6),
            clockIn: TestData.date(2026, 1, 6, 8),
            clockOut: TestData.date(2026, 1, 6, 16),
            notes: nil
        )

        // Storage keeps both, the screen shows only the Cafe's.
        XCTAssertEqual(store.storedSessions.count, 2)
        XCTAssertEqual(viewModel.workSessions.count, 1)
        let cafeShift = try XCTUnwrap(viewModel.workSessions.first)
        XCTAssertEqual(cafeShift.workplaceID, secondID)

        // Priced with each workplace's own rate.
        XCTAssertEqual(viewModel.breakdown(for: cafeShift).basePay, 8 * 50, accuracy: 0.01)
        XCTAssertEqual(viewModel.breakdown(for: mainShift).basePay, 8 * 100, accuracy: 0.01)
        XCTAssertEqual(viewModel.settings.hourlyRate, 100, "Editing the Cafe must not touch the main workplace")

        viewModel.switchWorkplace(to: nil)
        XCTAssertEqual(viewModel.workSessions.map(\.id), [mainShift.id])
    }

    func testMergeShowsEveryWorkplaceInHistoryOnly() throws {
        let (viewModel, _) = makeViewModel(sessions: [TestData.session(day: 5)])
        _ = try XCTUnwrap(viewModel.addWorkplace(named: "Cafe"))
        viewModel.addManualSession(
            date: TestData.date(2026, 1, 6),
            clockIn: TestData.date(2026, 1, 6, 8),
            clockOut: TestData.date(2026, 1, 6, 12),
            notes: nil
        )
        viewModel.setShowAllWorkplaces(true)
        XCTAssertEqual(viewModel.historySessions.count, 2)
        XCTAssertEqual(viewModel.workSessions.count, 1, "Pay and Home stay per workplace")
    }

    func testNoSwitchingWhileClockedIn() throws {
        let (viewModel, _) = makeViewModel()
        let secondID = try XCTUnwrap(viewModel.addWorkplace(named: "Cafe"))
        viewModel.clockIn()
        XCTAssertFalse(viewModel.switchWorkplace(to: nil))
        XCTAssertEqual(viewModel.activeWorkplaceKey, secondID)
        XCTAssertEqual(viewModel.activeSession?.workplaceID, secondID)
    }

    func testDeletingAWorkplaceNeverMovesItsShiftsIntoTheMainOne() throws {
        let mainShift = TestData.session(day: 5)
        let (viewModel, store) = makeViewModel(sessions: [mainShift])
        let secondID = try XCTUnwrap(viewModel.addWorkplace(named: "Cafe"))
        viewModel.addManualSession(
            date: TestData.date(2026, 1, 6),
            clockIn: TestData.date(2026, 1, 6, 8),
            clockOut: TestData.date(2026, 1, 6, 12),
            notes: nil
        )

        viewModel.deleteWorkplace(secondID)

        XCTAssertFalse(viewModel.hasMultipleWorkplaces)
        XCTAssertNil(viewModel.activeWorkplaceKey)
        XCTAssertEqual(store.storedSessions.map(\.id), [mainShift.id])
        XCTAssertEqual(viewModel.recentlyDeletedSessions.count, 1)
    }

    func testOlderShiftsWithoutAWorkplaceBelongToTheMainOne() throws {
        let shift = TestData.session(day: 5)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(shift)) as? [String: Any]
        )
        XCTAssertNil(object["workplaceID"], "Main-workplace shifts are saved exactly as before")
        object["workplaceID"] = "not-a-uuid"
        let decoded = try JSONDecoder().decode(WorkSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.workplaceID)
    }
}
