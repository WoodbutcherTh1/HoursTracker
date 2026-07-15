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
        XCTAssertTrue(viewModel.showDaySummary)
        XCTAssertEqual(
            viewModel.lastCompletedDayOfMonth,
            Calendar.current.component(.day, from: viewModel.sessions[0].date)
        )
        XCTAssertFalse(store.storedSessions[0].isOpen)
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

    func testManualSessionRejectsDuplicateDay() {
        let (viewModel, _) = makeViewModel()
        let day = TestData.date(2026, 3, 10)

        viewModel.addManualSession(
            date: day,
            clockIn: TestData.date(2026, 3, 10, 8),
            clockOut: TestData.date(2026, 3, 10, 16),
            notes: nil
        )
        viewModel.addManualSession(
            date: day,
            clockIn: TestData.date(2026, 3, 10, 9),
            clockOut: TestData.date(2026, 3, 10, 17),
            notes: nil
        )

        XCTAssertEqual(viewModel.sessions.count, 1)
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
}
