import XCTest
@testable import HoursTracker

@MainActor
final class DataSafetyTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataSafetyTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func completedShift(day: Int) -> WorkSession {
        TestData.session(day: day)
    }

    private func makeViewModel(sessions: [WorkSession]) -> (AppViewModel, InMemoryStore, DeletedSessionsStore, LocalBackupStore) {
        let store = InMemoryStore()
        store.storedSessions = sessions
        let trash = DeletedSessionsStore(directory: directory)
        let backups = LocalBackupStore(directory: directory.appendingPathComponent("Backups"))
        let viewModel = AppViewModel(
            store: store,
            locationManager: MockLocationReminderManager(),
            deletedSessions: trash,
            backups: backups
        )
        return (viewModel, store, trash, backups)
    }

    // MARK: Recently deleted

    func testDeleteMovesShiftToRecentlyDeletedAndOffersUndo() {
        let shift = completedShift(day: 3)
        let (viewModel, store, trash, _) = makeViewModel(sessions: [shift])

        viewModel.deleteSession(shift)

        XCTAssertTrue(store.storedSessions.isEmpty)
        XCTAssertEqual(trash.load().map(\.id), [shift.id])
        XCTAssertEqual(viewModel.undoableDeletion?.id, shift.id)
    }

    func testUndoPutsTheShiftBack() {
        let shift = completedShift(day: 3)
        let (viewModel, store, trash, _) = makeViewModel(sessions: [shift])

        viewModel.deleteSession(shift)
        viewModel.undoLastDeletion()

        XCTAssertEqual(store.storedSessions.map(\.id), [shift.id])
        XCTAssertTrue(trash.load().isEmpty)
        XCTAssertNil(viewModel.undoableDeletion)
    }

    func testBulkDeleteMovesEveryShiftToRecentlyDeleted() {
        let keep = completedShift(day: 1)
        let a = completedShift(day: 2)
        let b = completedShift(day: 3)
        let (viewModel, store, trash, _) = makeViewModel(sessions: [keep, a, b])

        viewModel.deleteSessions([a, b])

        XCTAssertEqual(store.storedSessions.map(\.id), [keep.id])
        XCTAssertEqual(Set(trash.load().map(\.id)), [a.id, b.id])
        XCTAssertEqual(viewModel.undoableDeletionCount, 2)
    }

    func testBulkUndoPutsEveryShiftBack() {
        let keep = completedShift(day: 1)
        let a = completedShift(day: 2)
        let b = completedShift(day: 3)
        let (viewModel, store, trash, _) = makeViewModel(sessions: [keep, a, b])

        viewModel.deleteSessions([a, b])
        viewModel.undoLastDeletion()

        XCTAssertEqual(Set(store.storedSessions.map(\.id)), [keep.id, a.id, b.id])
        XCTAssertTrue(trash.load().isEmpty)
        XCTAssertNil(viewModel.undoableDeletion)
        XCTAssertEqual(viewModel.undoableDeletionCount, 0)
    }

    func testRestoreFromRecentlyDeleted() {
        let keep = completedShift(day: 2)
        let shift = completedShift(day: 3)
        let (viewModel, store, _, _) = makeViewModel(sessions: [keep, shift])

        viewModel.deleteSession(shift)
        viewModel.restoreDeletedSession(id: shift.id)

        XCTAssertEqual(Set(store.storedSessions.map(\.id)), [keep.id, shift.id])
    }

    func testDeleteForeverRemovesFromBin() {
        let shift = completedShift(day: 3)
        let (viewModel, _, trash, _) = makeViewModel(sessions: [shift])

        viewModel.deleteSession(shift)
        viewModel.deleteForever(id: shift.id)

        XCTAssertTrue(trash.load().isEmpty)
    }

    func testBinDropsEntriesPastRetention() throws {
        let trash = DeletedSessionsStore(directory: directory)
        let shift = completedShift(day: 3)
        let longAgo = Date().addingTimeInterval(-(DeletedSessionsStore.retention + 60))
        try trash.add(shift, at: longAgo)
        XCTAssertTrue(trash.load().isEmpty)
    }

    // MARK: Automatic backups

    func testDailyBackupIsTakenOncePerDay() {
        let backups = LocalBackupStore(directory: directory)
        let sessions = [completedShift(day: 3)]
        XCTAssertTrue(backups.backupIfNeeded(settings: .default, sessions: sessions))
        XCTAssertFalse(backups.backupIfNeeded(settings: .default, sessions: sessions + [completedShift(day: 4)]))
        XCTAssertEqual(backups.list().count, 1)
        XCTAssertEqual(backups.list().first?.sessionCount, 1)
    }

    func testEmptyStateIsNeverBackedUp() {
        let backups = LocalBackupStore(directory: directory)
        XCTAssertFalse(backups.backupIfNeeded(settings: .default, sessions: []))
        XCTAssertTrue(backups.list().isEmpty)
    }

    func testKeepsOnlyTheNewestDailyBackups() {
        let backups = LocalBackupStore(directory: directory)
        let sessions = [completedShift(day: 3)]
        for dayOffset in 0..<(LocalBackupStore.keepDays + 3) {
            let date = Date().addingTimeInterval(TimeInterval(-dayOffset * 86_400))
            backups.backupIfNeeded(settings: .default, sessions: sessions, now: date)
        }
        XCTAssertLessThanOrEqual(backups.list().filter { !$0.isPreRestore }.count, LocalBackupStore.keepDays)
    }

    func testRestoreBackupReplacesDataAndSavesCurrentStateFirst() throws {
        let original = [completedShift(day: 3), completedShift(day: 4)]
        let (viewModel, store, _, backups) = makeViewModel(sessions: original)
        // The view model takes today's backup at launch.
        let backup = try XCTUnwrap(backups.list().first)

        viewModel.deleteSession(original[0])
        viewModel.deleteSession(original[1])
        viewModel.addManualSession(
            date: TestData.date(2026, 1, 9),
            clockIn: TestData.date(2026, 1, 9, 8),
            clockOut: TestData.date(2026, 1, 9, 12),
            notes: nil
        )
        try viewModel.restoreBackup(backup)

        XCTAssertEqual(Set(store.storedSessions.map(\.id)), Set(original.map(\.id)))
        XCTAssertTrue(backups.list().contains(where: \.isPreRestore))
    }
}
