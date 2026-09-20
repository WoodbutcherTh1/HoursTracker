import XCTest
@testable import HoursTracker

final class OvertimeCalculatorTests: XCTestCase {
    private var settings: WorkplaceSettings!

    override func setUp() {
        super.setUp()
        settings = WorkplaceSettings(
            workplaceName: "Test",
            contractorName: nil,
            workerFullName: "Worker",
            workerIDNumber: "123",
            employeeNumber: "456",
            hourlyRate: 100,
            dailyGasAllowance: 35,
            standardDayHours: 8.6,
            ot125HoursCap: 2.0,
            locationLatitude: nil,
            locationLongitude: nil,
            locationRadiusMeters: 150,
            maritalStatus: .single,
            hasChildren: false,
            numberOfChildren: 0,
            spouseEmployed: false,
            modifiedAt: Date()
        )
    }

    func testRegularHoursOnly() {
        let result = OvertimeCalculator.breakdown(totalHours: 8.0, settings: settings)
        XCTAssertEqual(result.regularHours, 8.0, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.totalPay, 835, accuracy: 0.01) // 800 + 35 gas
        XCTAssertLessThan(result.netPay, result.grossPay)
        XCTAssertGreaterThan(result.netPay, 0)
    }

    func testExactlyStandardDayHours() {
        let result = OvertimeCalculator.breakdown(totalHours: 8.6, settings: settings)
        XCTAssertEqual(result.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.totalPay, 895, accuracy: 0.01) // 860 + 35
    }

    func testOT125Only() {
        let result = OvertimeCalculator.breakdown(totalHours: 10.0, settings: settings)
        XCTAssertEqual(result.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 1.4, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.001)
        // 860 + 1.4*125 + 35 = 1070
        XCTAssertEqual(result.totalPay, 1070, accuracy: 0.01)
    }

    func testOT125CapAndOT150() {
        let result = OvertimeCalculator.breakdown(totalHours: 12.0, settings: settings)
        XCTAssertEqual(result.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 2.0, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 1.4, accuracy: 0.001)
        // 860 + 250 + 210 + 35 = 1355
        XCTAssertEqual(result.totalPay, 1355, accuracy: 0.01)
    }

    func testZeroHours() {
        let result = OvertimeCalculator.breakdown(totalHours: 0, settings: settings)
        XCTAssertEqual(result.regularHours, 0, accuracy: 0.001)
        XCTAssertEqual(result.totalPay, 35, accuracy: 0.01)
    }

    func testAggregateMultipleSessions() {
        // Distinct days: overtime and the gas allowance are per calendar day,
        // so each day gets its own standard-hours allowance and gas payment.
        let sessions = [
            makeSession(hours: 8.6, daysAgo: 1),
            makeSession(hours: 10.0, daysAgo: 0)
        ]
        let result = OvertimeCalculator.aggregate(sessions: sessions, settings: settings)
        XCTAssertEqual(result.regularHours, 17.2, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 1.4, accuracy: 0.001)
        XCTAssertEqual(result.gasAllowance, 70, accuracy: 0.01)
        XCTAssertEqual(result.grossPay, result.totalPay, accuracy: 0.01)
        XCTAssertLessThan(result.netPay, result.grossPay)
    }

    func testCreditPointsBaseResident() {
        XCTAssertEqual(TaxCreditPointsCalculator.creditPoints(for: settings), 2.25, accuracy: 0.001)
    }

    func testCreditPointsWithChildrenAndUnemployedSpouse() {
        settings.maritalStatus = .married
        settings.spouseEmployed = false
        settings.hasChildren = true
        settings.numberOfChildren = 2
        // 2.25 + 2 children + 0.5 spouse = 4.75
        XCTAssertEqual(TaxCreditPointsCalculator.creditPoints(for: settings), 4.75, accuracy: 0.001)
        let withKids = OvertimeCalculator.breakdown(totalHours: 8.6, settings: settings)
        settings.numberOfChildren = 0
        settings.hasChildren = false
        settings.spouseEmployed = true
        let without = OvertimeCalculator.breakdown(totalHours: 8.6, settings: settings)
        XCTAssertGreaterThanOrEqual(withKids.netPay, without.netPay)
    }

    private func makeSession(hours: Double, daysAgo: Int = 0) -> WorkSession {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysAgo, to: Date())!)
        let start = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
        let end = start.addingTimeInterval(hours * 3600)
        return WorkSession(
            date: day,
            clockIn: start,
            clockOut: end,
            isManualEntry: false
        )
    }

    // MARK: - Sick days

    func testSickPayPercentageSchedule() {
        XCTAssertEqual(OvertimeCalculator.sickPayPercentage(streakDayNumber: 1), 0.0)
        XCTAssertEqual(OvertimeCalculator.sickPayPercentage(streakDayNumber: 2), 0.5)
        XCTAssertEqual(OvertimeCalculator.sickPayPercentage(streakDayNumber: 3), 0.5)
        XCTAssertEqual(OvertimeCalculator.sickPayPercentage(streakDayNumber: 4), 1.0)
        XCTAssertEqual(OvertimeCalculator.sickPayPercentage(streakDayNumber: 9), 1.0)
    }

    func testSingleSickDayIsUnpaid() {
        let sick = TestData.sickDay(year: 2026, month: 1, day: 12) // Monday
        let result = OvertimeCalculator.breakdown(for: sick, settings: settings)
        XCTAssertEqual(result.totalHours, 0, accuracy: 0.001)
        XCTAssertEqual(result.basePay, 0, accuracy: 0.01)
        XCTAssertEqual(result.gasAllowance, 0, accuracy: 0.01)
    }

    func testFourConsecutiveSickDaysFollowTheLegalSchedule() {
        let sessions = (12...15).map { TestData.sickDay(year: 2026, month: 1, day: $0) } // Mon–Thu
        let results = OvertimeCalculator.dayAwareBreakdowns(sessions: sessions, settings: settings)
        // Day 1: unpaid, days 2–3: half a standard day, day 4: a full standard day.
        let halfDay = settings.standardDayHours * settings.hourlyRate * 0.5
        let fullDay = settings.standardDayHours * settings.hourlyRate
        XCTAssertEqual(results[0].breakdown.basePay, 0, accuracy: 0.01)
        XCTAssertEqual(results[1].breakdown.basePay, halfDay, accuracy: 0.01)
        XCTAssertEqual(results[2].breakdown.basePay, halfDay, accuracy: 0.01)
        XCTAssertEqual(results[3].breakdown.basePay, fullDay, accuracy: 0.01)
    }

    func testRestDayGapResetsTheSickStreak() {
        // Jan 16 2026 is a Friday, Jan 17 a Saturday (rest day, not marked sick),
        // Jan 18 a Sunday marked sick again — the rest-day gap must NOT bridge
        // the streak, so Jan 18 starts back at day 1 (unpaid).
        let firstRun = [TestData.sickDay(year: 2026, month: 1, day: 15), TestData.sickDay(year: 2026, month: 1, day: 16)]
        let afterGap = TestData.sickDay(year: 2026, month: 1, day: 18)
        let results = OvertimeCalculator.dayAwareBreakdowns(sessions: firstRun + [afterGap], settings: settings)
        let resumed = results.first { Calendar.current.isDate($0.session.date, inSameDayAs: afterGap.date) }
        XCTAssertNotNil(resumed)
        XCTAssertEqual(resumed?.breakdown.basePay ?? -1, 0, accuracy: 0.01)
    }
}

final class PayrollPeriodTests: XCTestCase {
    func testCalendarMonthWhenStartDayIsOne() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 15
        let date = Calendar.current.date(from: comps)!
        let period = HistoryPeriodHelper.payrollPeriod(containing: date, startDay: 1)
        XCTAssertEqual(Calendar.current.component(.day, from: period.start), 1)
        XCTAssertEqual(Calendar.current.component(.month, from: period.start), 7)
        XCTAssertEqual(Calendar.current.component(.day, from: period.end), 31)
        XCTAssertEqual(Calendar.current.component(.month, from: period.end), 7)
    }

    func testCustomStartDaySpansMonths() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 15
        let date = Calendar.current.date(from: comps)!
        let period = HistoryPeriodHelper.payrollPeriod(containing: date, startDay: 10)
        XCTAssertEqual(Calendar.current.component(.day, from: period.start), 10)
        XCTAssertEqual(Calendar.current.component(.month, from: period.start), 7)
        XCTAssertEqual(Calendar.current.component(.day, from: period.end), 9)
        XCTAssertEqual(Calendar.current.component(.month, from: period.end), 8)
        XCTAssertTrue(period.contains(date))
    }

    func testDateBeforeStartBelongsToPreviousCycle() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 5
        let date = Calendar.current.date(from: comps)!
        let period = HistoryPeriodHelper.payrollPeriod(containing: date, startDay: 10)
        XCTAssertEqual(Calendar.current.component(.month, from: period.start), 6)
        XCTAssertEqual(Calendar.current.component(.day, from: period.start), 10)
        XCTAssertEqual(Calendar.current.component(.month, from: period.end), 7)
        XCTAssertEqual(Calendar.current.component(.day, from: period.end), 9)
    }
}

final class TimesheetScannerParserTests: XCTestCase {
    func testParseLineOrientedTimesheet() async throws {
        let text = """
        Date In Out
        12/07/2026 08:00 17:00
        13/07/2026 07:30 16:45
        """
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].totalHours, 9.0, accuracy: 0.01)
        XCTAssertTrue(drafts[0].isSelected)
    }

    func testParseHebrewKeywordsLine() async throws {
        let text = "תאריך 01/07/2026 כניסה 08:15 יציאה 17:00"
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].totalHours, 8.75, accuracy: 0.01)
    }

    func testGlobalPairingAcrossSplitLines() async throws {
        let text = """
        12.07.2026
        08:00
        17:30
        13.07
        09:00
        18:00
        """
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertGreaterThanOrEqual(drafts.count, 2)
    }

    func testFallbackWhenNoSessions() async throws {
        let result = await TimesheetScannerManager.shared.parseResult(from: "hello world nothing useful")
        XCTAssertTrue(result.usedManualFallback)
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertTrue(result.drafts[0].needsManualReview)
    }
}

@MainActor
final class BlankTimesheetViewModelTests: XCTestCase {
    private let calendar = Calendar.current

    func testAnalyzeFreeTextFillsFormRows() async {
        let vm = BlankTimesheetViewModel()
        vm.loadPeriod(startDay: 1)
        vm.freeText = """
        12/07/2026 08:00 17:00
        13/07/2026 07:30 16:45
        """

        await vm.analyzeFreeText(startDay: 1)

        XCTAssertEqual(vm.mode, .form)
        XCTAssertNil(vm.analyzeError)
        XCTAssertEqual(vm.filledCount, 2)
        XCTAssertNotNil(vm.analyzeNotice)
    }

    func testAnalyzeFreeTextRejectsUnparseableInput() async {
        let vm = BlankTimesheetViewModel()
        vm.loadPeriod(startDay: 1)
        vm.freeText = "nothing useful here"

        await vm.analyzeFreeText(startDay: 1)

        XCTAssertNotNil(vm.analyzeError)
        XCTAssertEqual(vm.filledCount, 0)
    }

    func testGridRowToDraftSkipsEmptyTimes() {
        let day = Calendar.current.startOfDay(for: Date())
        let empty = TimesheetGridRow(date: day)
        XCTAssertNil(empty.toDraft())

        let filled = TimesheetGridRow(
            date: day,
            clockIn: day.addingTimeInterval(8 * 3600),
            clockOut: day.addingTimeInterval(17 * 3600)
        )
        XCTAssertNotNil(filled.toDraft())
        XCTAssertEqual(filled.toDraft()?.totalHours ?? 0, 9, accuracy: 0.01)
    }

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
        // No loadPeriod called - rows remain empty.
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

// MARK: - Weekly overtime cap

final class WeeklyOvertimeCapTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func session(
        day: Int, month: Int = 8, year: Int = 2026,
        inHour: Int = 8, outHour: Int = 18
    ) -> WorkSession {
        let d = date(year, month, day)
        return WorkSession(
            date: d,
            clockIn: calendar.date(bySettingHour: inHour, minute: 0, second: 0, of: d)!,
            clockOut: calendar.date(bySettingHour: outHour, minute: 0, second: 0, of: d)
        )
    }

    private func settings(
        weeklyStandardHours: Double = 42,
        weeklyOvertimeCapHours: Double = 12
    ) -> WorkplaceSettings {
        var s = WorkplaceSettings.default
        s.hourlyRate = 100
        s.standardDayHours = 8.6
        s.ot125HoursCap = 2
        s.weeklyStandardHours = weeklyStandardHours
        s.weeklyOvertimeCapHours = weeklyOvertimeCapHours
        return s
    }

    /// 6 days × 10h = 60h total; daily OT = 6 × 1.4h = 8.4h already at OT rates;
    /// weekly excess = 60 - 42 = 18h, but daily OT already covers 8.4h;
    /// remaining 9.6h need to move from regular to weekly OT.
    func testWeeklyOTPromotesRegularHoursAboveThreshold() {
        let sessions = (3...8).map { session(day: $0, inHour: 8, outHour: 18) }
        let result = OvertimeCalculator.aggregate(sessions: sessions, settings: settings())

        // Should have some hours moved from regular to weekly OT.
        let dailyRegularHours = 6 * 8.6 // 51.6h at daily 100%
        let dailyOTHours = 6 * 1.4 // 8.4h at daily 125%
        let weeklyExcess = 60.0 - 42.0 // 18h
        let needsWeeklyOT = weeklyExcess - dailyOTHours // 9.6h

        XCTAssertGreaterThan(result.ot125Hours, dailyOTHours,
            "weekly OT should add to the OT125 bucket")
        XCTAssertLessThan(result.regularHours, dailyRegularHours,
            "regular bucket should shrink when weekly OT applies")
        XCTAssertEqual(result.totalHours, 60.0, accuracy: 0.01)
    }

    /// When total weekly hours ≤ standard (42h), no weekly adjustment occurs.
    func testWeeklyOTDoesNotApplyWhenUnderThreshold() {
        // 4 × 8h days = 32h/week: each day is under the 8.6h daily standard
        // (so no DAILY OT either) and the week is under 42h, so nothing should
        // move out of the regular bucket — weekly or otherwise.
        let sessions4 = (3...6).map { session(day: $0, inHour: 8, outHour: 16) }
        let result = OvertimeCalculator.aggregate(sessions: sessions4, settings: settings())

        XCTAssertEqual(result.regularHours, 32.0, accuracy: 0.01)
        XCTAssertEqual(result.ot125Hours, 0, accuracy: 0.01)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.01)
    }

    /// Open sessions must be excluded from aggregate.
    func testAggregateExcludesOpenSessions() {
        let closed = session(day: 3, inHour: 8, outHour: 17) // 9h
        let open = WorkSession(
            date: date(2026, 8, 4),
            clockIn: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date(2026, 8, 4))!,
            clockOut: nil
        )
        let result = OvertimeCalculator.aggregate(sessions: [closed, open], settings: settings())

        XCTAssertEqual(result.totalHours, 9.0, accuracy: 0.01,
            "open session should not count toward aggregate")
    }
}
