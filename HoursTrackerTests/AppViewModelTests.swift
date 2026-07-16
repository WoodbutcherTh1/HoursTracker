import XCTest
@testable import HoursTracker

@MainActor
final class AppViewModelTests: XCTestCase {
    private func makeViewModel(
        sessions: [WorkSession] = [],
        store: InMemoryStore = InMemoryStore()
    ) -> (viewModel: AppViewModel, store: InMemoryStore) {
        store.storedSessions = sessions
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())
        return (viewModel, store)
    }

    private func openSessionYesterday() -> WorkSession {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        return WorkSession(
            date: calendar.startOfDay(for: yesterday),
            clockIn: calendar.date(bySettingHour: 20, minute: 0, second: 0, of: yesterday)!,
            clockOut: nil
        )
    }

    func testClockInCreatesOpenSessionAndPersists() {
        let (viewModel, store) = makeViewModel()

        viewModel.clockIn()

        XCTAssertTrue(viewModel.isClockedIn)
        XCTAssertEqual(store.storedSessions.count, 1)
        XCTAssertTrue(store.storedSessions[0].isOpen)
    }

    func testSecondClockInSameDayAfterClockOutIsAllowed() {
        let (viewModel, _) = makeViewModel()

        viewModel.clockIn()
        viewModel.clockOut()
        viewModel.clockIn()

        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertTrue(viewModel.isClockedIn)
    }

    func testClockOutClosesSessionAndShowsSummary() {
        let (viewModel, store) = makeViewModel()

        viewModel.clockIn()
        viewModel.clockOut()

        XCTAssertFalse(viewModel.isClockedIn)
        XCTAssertNotNil(viewModel.lastCompletedBreakdown)
        XCTAssertNotNil(viewModel.lastCompletedSessionID)
        XCTAssertEqual(viewModel.lastCompletedSessionID, store.storedSessions[0].id)
        XCTAssertTrue(viewModel.showDaySummary)
        XCTAssertFalse(store.storedSessions[0].isOpen)
    }

    func testSecondShiftSummaryIsForThatShiftOnly() throws {
        let day = Calendar.current.startOfDay(for: Date())
        // Morning shift already completed: 8 hours.
        let morning = WorkSession(
            date: day,
            clockIn: day.addingTimeInterval(8 * 3600),
            clockOut: day.addingTimeInterval(16 * 3600)
        )
        let (viewModel, _) = makeViewModel(sessions: [morning])

        viewModel.clockIn()
        viewModel.clockOut()

        let completedID = try XCTUnwrap(viewModel.lastCompletedSessionID)
        XCTAssertNotEqual(completedID, morning.id)
        let summary = try XCTUnwrap(viewModel.lastCompletedBreakdown)
        let justClosed = try XCTUnwrap(viewModel.sessions.first { $0.id == completedID })

        // Summary matches the just-closed shift, not the whole day (~8h+).
        XCTAssertEqual(summary.totalHours, justClosed.effectiveHours, accuracy: 0.05)
        XCTAssertLessThan(summary.totalHours, 1.0)

        let dayTotal = OvertimeCalculator.aggregate(
            sessions: viewModel.sessions.filter { !$0.isOpen },
            settings: viewModel.settings
        )
        XCTAssertGreaterThan(dayTotal.totalHours, 7.0)
        XCTAssertNotEqual(summary.totalHours, dayTotal.totalHours, accuracy: 0.5)
    }

    func testDeleteLastCompletedSessionRemovesOnlyThatShift() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let earlier = WorkSession(
            date: day,
            clockIn: day.addingTimeInterval(8 * 3600),
            clockOut: day.addingTimeInterval(12 * 3600)
        )
        let (viewModel, store) = makeViewModel(sessions: [earlier])

        viewModel.clockIn()
        viewModel.clockOut()

        let completedID = try XCTUnwrap(viewModel.lastCompletedSessionID)
        XCTAssertNotEqual(completedID, earlier.id)
        XCTAssertEqual(viewModel.sessions.count, 2)

        let justCompleted = try XCTUnwrap(viewModel.sessions.first { $0.id == completedID })
        viewModel.deleteSession(justCompleted)
        viewModel.dismissDaySummary()

        XCTAssertEqual(viewModel.sessions.map(\.id), [earlier.id])
        XCTAssertEqual(store.storedSessions.map(\.id), [earlier.id])
        XCTAssertNil(viewModel.lastCompletedSessionID)
        XCTAssertFalse(viewModel.showDaySummary)
    }

    func testSessionOpenSinceYesterdayIsStillActive() {
        let yesterdaysSession = openSessionYesterday()
        let (viewModel, _) = makeViewModel(sessions: [yesterdaysSession])

        XCTAssertEqual(viewModel.activeSession?.id, yesterdaysSession.id)
        XCTAssertTrue(viewModel.isClockedIn)
    }

    func testClockInBlockedWhileYesterdaysSessionIsOpen() {
        let yesterdaysSession = openSessionYesterday()
        let (viewModel, _) = makeViewModel(sessions: [yesterdaysSession])

        XCTAssertFalse(viewModel.canClockInToday)
        viewModel.clockIn()

        XCTAssertEqual(viewModel.sessions.count, 1)
    }

    func testClockOutClosesYesterdaysOpenSession() {
        let yesterdaysSession = openSessionYesterday()
        let (viewModel, store) = makeViewModel(sessions: [yesterdaysSession])

        viewModel.clockOut()

        XCTAssertFalse(viewModel.isClockedIn)
        XCTAssertFalse(store.storedSessions[0].isOpen)
    }

    func testManualSessionAllowsMultipleShiftsSameDay() {
        let (viewModel, _) = makeViewModel()
        let day = TestData.date(2026, 3, 10)

        viewModel.addManualSession(
            date: day,
            clockIn: TestData.date(2026, 3, 10, 8),
            clockOut: TestData.date(2026, 3, 10, 12),
            notes: nil
        )
        viewModel.addManualSession(
            date: day,
            clockIn: TestData.date(2026, 3, 10, 14),
            clockOut: TestData.date(2026, 3, 10, 18),
            notes: nil
        )

        XCTAssertEqual(viewModel.sessions.count, 2)
    }

    func testDeleteSessionPersists() {
        let session = TestData.session(day: 1)
        let (viewModel, store) = makeViewModel(sessions: [session])

        viewModel.deleteSession(session)

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertTrue(store.storedSessions.isEmpty)
    }

    func testSaveFailureSurfacesErrorMessage() {
        let store = InMemoryStore()
        let (viewModel, _) = makeViewModel(store: store)
        store.saveError = NSError(domain: "test", code: 1)

        viewModel.clockIn()

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSaveSettingsFailureSurfacesErrorMessage() {
        let store = InMemoryStore()
        let (viewModel, _) = makeViewModel(store: store)
        store.saveError = NSError(domain: "test", code: 1)

        viewModel.saveSettings(TestData.settings())

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testDeleteAllUserDataClearsLocalStateAndUsesLocalSettingsSave() async {
        let session = TestData.session(day: 1)
        let store = InMemoryStore()
        store.isCloudSyncSupported = true
        store.storedSessions = [session]
        store.storedSettings = TestData.settings()
        let location = MockLocationReminderManager()
        let viewModel = AppViewModel(store: store, locationManager: location)

        let exportURL = try? ExportTempFileStore.write(
            data: Data("leftover".utf8),
            fileName: "HoursReport-delete-all.txt"
        )

        viewModel.deleteAllUserData()

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertEqual(viewModel.settings.workerIDNumber, "")
        XCTAssertEqual(viewModel.settings.workplaceName, "")
        XCTAssertEqual(viewModel.settings.hourlyRate, WorkplaceSettings.default.hourlyRate)
        XCTAssertEqual(store.saveSettingsLocallyCallCount, 1)
        XCTAssertEqual(location.stopReminderCalls, 1)
        if let exportURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
        }

        let deadline = Date().addingTimeInterval(2)
        while store.purgeCloudCallCount == 0, Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(store.purgeCloudCallCount, 1)
        XCTAssertEqual(store.lastPurgedSessionIDs, [session.id])
    }

    func testDeleteAllUserDataSurfacesCloudPurgeFailure() async {
        let store = InMemoryStore()
        store.isCloudSyncSupported = true
        store.purgeCloudError = NSError(domain: "test", code: 99)
        store.storedSessions = [TestData.session(day: 2)]
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        viewModel.deleteAllUserData()

        let deadline = Date().addingTimeInterval(2)
        while viewModel.errorMessage == nil, Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.errorMessage, L10n.privacyDeleteCloudPartialFailure)
    }
}
