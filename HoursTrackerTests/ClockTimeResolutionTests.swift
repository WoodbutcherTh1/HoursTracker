import XCTest
@testable import HoursTracker

final class ClockTimeResolutionTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        return calendar.date(from: c)!
    }

    func testSwappedDayShiftIsCorrectedToMorningStart() {
        // OCR/RTL often yields evening first, morning second → fake 14h overnight.
        let evening = date(2024, 7, 13, 17, 2)
        let morning = date(2024, 7, 13, 7, 22)

        let resolved = WorkSession.resolveClockPair(
            clockIn: evening,
            clockOut: morning,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.hour, from: resolved.clockIn), 7)
        XCTAssertEqual(calendar.component(.minute, from: resolved.clockIn), 22)
        XCTAssertEqual(calendar.component(.hour, from: resolved.clockOut), 17)
        XCTAssertEqual(calendar.component(.minute, from: resolved.clockOut), 2)
        XCTAssertEqual(resolved.clockOut.timeIntervalSince(resolved.clockIn) / 3600, 9 + 40.0 / 60, accuracy: 0.01)
    }

    func testAlreadyWrongOvernightPairIsCorrected() {
        let evening = date(2024, 7, 13, 17, 2)
        let nextMorning = date(2024, 7, 14, 7, 22)

        let resolved = WorkSession.resolveClockPair(
            clockIn: evening,
            clockOut: nextMorning,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.day, from: resolved.clockIn), 13)
        XCTAssertEqual(calendar.component(.hour, from: resolved.clockIn), 7)
        XCTAssertEqual(calendar.component(.hour, from: resolved.clockOut), 17)
        let hours = resolved.clockOut.timeIntervalSince(resolved.clockIn) / 3600
        XCTAssertEqual(hours, 9 + 40.0 / 60, accuracy: 0.01)
    }

    func testGenuineShortOvernightIsPreserved() {
        let night = date(2024, 7, 13, 22, 0)
        let morning = date(2024, 7, 13, 6, 0)

        let resolved = WorkSession.resolveClockPair(
            clockIn: night,
            clockOut: morning,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.hour, from: resolved.clockIn), 22)
        XCTAssertEqual(calendar.component(.day, from: resolved.clockOut), 14)
        XCTAssertEqual(calendar.component(.hour, from: resolved.clockOut), 6)
        XCTAssertEqual(resolved.clockOut.timeIntervalSince(resolved.clockIn) / 3600, 8, accuracy: 0.01)
    }

    func testNormalSameDayShiftUnchanged() {
        let start = date(2024, 7, 13, 8, 0)
        let end = date(2024, 7, 13, 17, 0)

        let resolved = WorkSession.resolveClockPair(
            clockIn: start,
            clockOut: end,
            calendar: calendar
        )

        XCTAssertEqual(resolved.clockIn, start)
        XCTAssertEqual(resolved.clockOut, end)
    }
}

final class ImportConflictTests: XCTestCase {
    @MainActor
    func testConflictingDaysDetectsExistingShifts() {
        let store = InMemoryStore()
        let existing = TestData.session(day: 13, inHour: 8, outHour: 17)
        store.storedSessions = [existing]
        store.storedSettings = TestData.settings()

        let vm = AppViewModel(store: store, locationManager: MockLocationReminderManager())
        let draft = ScannedSessionDraft(
            date: TestData.date(2026, 1, 13),
            clockIn: TestData.date(2026, 1, 13, 7, 0),
            clockOut: TestData.date(2026, 1, 13, 16, 0)
        )

        let conflicts = vm.conflictingDays(for: [draft])
        XCTAssertEqual(conflicts.count, 1)
    }

    @MainActor
    func testImportReplaceOverwritesExistingDay() {
        let store = InMemoryStore()
        let existing = TestData.session(day: 13, inHour: 8, outHour: 17)
        store.storedSessions = [existing]
        store.storedSettings = TestData.settings()

        let vm = AppViewModel(store: store, locationManager: MockLocationReminderManager())
        let day = TestData.date(2026, 1, 13)
        let draft = ScannedSessionDraft(
            date: day,
            clockIn: TestData.date(2026, 1, 13, 7, 30),
            clockOut: TestData.date(2026, 1, 13, 16, 30)
        )

        vm.importScannedSessions([draft], overwriteDays: [Calendar.current.startOfDay(for: day)])

        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(Calendar.current.component(.hour, from: vm.sessions[0].clockIn), 7)
        XCTAssertEqual(Calendar.current.component(.minute, from: vm.sessions[0].clockIn), 30)
    }
}
