import XCTest
@testable import HoursTracker

@MainActor
final class BlankTimesheetViewModelTests: XCTestCase {
    private let calendar = Calendar.current

    // MARK: - canAddRow

    func testCanAddRowFalseWhenLastRowIsPeriodEnd() {
        let vm = BlankTimesheetViewModel()
        vm.loadPeriod(startDay: 1)
        let end = vm.periodEnd
        // Replace rows with a single row sitting exactly on the period end.
        vm.rows = [TimesheetGridRow(date: end)]

        XCTAssertFalse(vm.canAddRow, "canAddRow must be false when the last row is the period end")
    }

    func testCanAddRowTrueWhenLastRowIsOneDayBeforePeriodEnd() {
        let vm = BlankTimesheetViewModel()
        vm.loadPeriod(startDay: 1)
        let end = vm.periodEnd
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        vm.rows = [TimesheetGridRow(date: dayBefore)]

        XCTAssertTrue(vm.canAddRow, "canAddRow must be true when the last row is one day before period end")
    }

    func testCanAddRowFalseWhenRowsIsEmpty() {
        let vm = BlankTimesheetViewModel()
        // No loadPeriod called – rows remain empty.
        XCTAssertFalse(vm.canAddRow, "canAddRow must be false when there are no rows")
    }

    // MARK: - addRow bounds

    func testAddRowDoesNotAddPastPeriodEnd() {
        let vm = BlankTimesheetViewModel()
        vm.loadPeriod(startDay: 1)
        let end = vm.periodEnd
        vm.rows = [TimesheetGridRow(date: end)]

        let countBefore = vm.rows.count
        vm.addRow()

        XCTAssertEqual(vm.rows.count, countBefore, "addRow must not append a row when already at period end")
    }

    func testAddRowAddsLastDayOfPeriodWhenOneDayBefore() {
        let vm = BlankTimesheetViewModel()
        vm.loadPeriod(startDay: 1)
        let end = vm.periodEnd
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        vm.rows = [TimesheetGridRow(date: dayBefore)]

        vm.addRow()

        XCTAssertEqual(vm.rows.count, 2, "addRow must succeed when last row is one day before period end")
        XCTAssertTrue(
            calendar.isDate(vm.rows.last!.date, inSameDayAs: end),
            "The added row should be the period end day"
        )
    }

    func testAddRowDoesNothingWhenRowsEmpty() {
        let vm = BlankTimesheetViewModel()
        // rows is empty; canAddRow is false, so addRow should be a no-op.
        vm.addRow()
        XCTAssertTrue(vm.rows.isEmpty, "addRow must not append when there are no rows")
    }

    // MARK: - periodEnd updates on period shift

    func testShiftPeriodUpdatesPeriodEnd() {
        let vm = BlankTimesheetViewModel()
        vm.loadPeriod(startDay: 1)
        let originalEnd = vm.periodEnd

        vm.shiftPeriod(by: 1, startDay: 1)

        XCTAssertNotEqual(
            vm.periodEnd, originalEnd,
            "periodEnd must update when the period is shifted"
        )
        // Forward shift: new end should be later than original.
        XCTAssertGreaterThan(vm.periodEnd, originalEnd)
    }

    func testShiftPeriodBackwardUpdatesPeriodEnd() {
        let vm = BlankTimesheetViewModel()
        vm.loadPeriod(startDay: 1)
        let originalEnd = vm.periodEnd

        vm.shiftPeriod(by: -1, startDay: 1)

        XCTAssertLessThan(vm.periodEnd, originalEnd, "Backward shift must yield an earlier period end")
    }

    // MARK: - Off-by-one: full period still loads with last-day addable removed

    func testLoadPeriodLastDayIsBlockedFromAdding() {
        // After loadPeriod the rows fill the whole period; last row IS period end,
        // so canAddRow must be false (the period is already complete).
        let vm = BlankTimesheetViewModel()
        vm.loadPeriod(startDay: 1)

        let lastRowDate = calendar.startOfDay(for: vm.rows.last!.date)
        let periodEndDate = calendar.startOfDay(for: vm.periodEnd)
        XCTAssertEqual(lastRowDate, periodEndDate, "loadPeriod must fill up to and including periodEnd")
        XCTAssertFalse(vm.canAddRow, "canAddRow must be false immediately after a full loadPeriod")
    }
}
