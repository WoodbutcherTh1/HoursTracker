import XCTest
@testable import HoursTracker

@MainActor
final class BlankTimesheetViewModelTests: XCTestCase {
    private var calendar: Calendar {
        Calendar.current
    }

    private func date(year: Int = 2026, month: Int = 7, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testApplyDraftsPreservesExistingRowsForUnscannedDays() {
        let viewModel = BlankTimesheetViewModel()
        let preservedDay = date(day: 2)
        let scannedDay = date(day: 3)
        let preservedClockIn = date(day: 2, hour: 8, minute: 15)
        let preservedClockOut = date(day: 2, hour: 16, minute: 45)
        let previousScannedClockIn = date(day: 3, hour: 7, minute: 30)
        let previousScannedClockOut = date(day: 3, hour: 15, minute: 30)
        let scannedClockIn = date(day: 3, hour: 9)
        let scannedClockOut = date(day: 3, hour: 17)

        viewModel.rows = [
            TimesheetGridRow(date: preservedDay, clockIn: preservedClockIn, clockOut: preservedClockOut),
            TimesheetGridRow(date: scannedDay, clockIn: previousScannedClockIn, clockOut: previousScannedClockOut)
        ]

        viewModel.apply(
            drafts: [
                ScannedSessionDraft(date: scannedDay, clockIn: scannedClockIn, clockOut: scannedClockOut)
            ],
            startDay: 1
        )

        let preservedRow = viewModel.rows.first { calendar.isDate($0.date, inSameDayAs: preservedDay) }
        XCTAssertEqual(preservedRow?.clockIn, preservedClockIn)
        XCTAssertEqual(preservedRow?.clockOut, preservedClockOut)

        let scannedRow = viewModel.rows.first { calendar.isDate($0.date, inSameDayAs: scannedDay) }
        XCTAssertEqual(scannedRow?.clockIn, scannedClockIn)
        XCTAssertEqual(scannedRow?.clockOut, scannedClockOut)
    }
}
