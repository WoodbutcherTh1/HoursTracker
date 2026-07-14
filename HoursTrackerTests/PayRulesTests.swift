import XCTest
@testable import HoursTracker

final class PayRulesTests: XCTestCase {
    private var settings: WorkplaceSettings!

    override func setUp() {
        super.setUp()
        // rate 100, gas 35, standard day 8.6h, OT125 cap 2h
        settings = TestData.settings()
    }

    // MARK: - Multi-session days share one daily allowance

    func testTwoSessionsSameDayShareDailyOvertimeAllowance() {
        let first = TestData.session(day: 1, inHour: 6, outHour: 11)   // 5h
        let second = TestData.session(day: 1, inHour: 12, outHour: 17) // 5h → 10h day

        let total = OvertimeCalculator.aggregate(sessions: [first, second], settings: settings)

        XCTAssertEqual(total.totalHours, 10, accuracy: 0.001)
        XCTAssertEqual(total.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(total.ot125Hours, 1.4, accuracy: 0.001)
        XCTAssertEqual(total.ot150Hours, 0, accuracy: 0.001)
        // 8.6×100 + 1.4×125 + gas once
        XCTAssertEqual(total.grossPay, 860 + 175 + 35, accuracy: 0.01)
    }

    func testMarginalSplitAcrossSessionsSumsToDayTotal() {
        let first = TestData.session(day: 1, inHour: 6, outHour: 11)
        let second = TestData.session(day: 1, inHour: 12, outHour: 17)

        // Input intentionally unordered — attribution must follow clock-in order.
        let parts = OvertimeCalculator.breakdowns(forDay: [second, first], settings: settings)

        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].session.id, first.id)
        XCTAssertEqual(parts[0].breakdown.regularHours, 5, accuracy: 0.001)
        XCTAssertEqual(parts[0].breakdown.gasAllowance, 35, accuracy: 0.001)
        XCTAssertEqual(parts[1].breakdown.regularHours, 3.6, accuracy: 0.001)
        XCTAssertEqual(parts[1].breakdown.ot125Hours, 1.4, accuracy: 0.001)
        XCTAssertEqual(parts[1].breakdown.gasAllowance, 0, accuracy: 0.001)

        let summedGross = parts.reduce(0) { $0 + $1.breakdown.grossPay }
        let total = OvertimeCalculator.aggregate(sessions: [first, second], settings: settings)
        XCTAssertEqual(summedGross, total.grossPay, accuracy: 0.01)

        let summedNet = parts.reduce(0) { $0 + $1.breakdown.netPay }
        XCTAssertEqual(summedNet, total.netPay, accuracy: 0.01)
    }

    func testGasAllowancePaidOncePerDayAcrossDistinctDays() {
        let dayOneA = TestData.session(day: 1, inHour: 8, outHour: 12)
        let dayOneB = TestData.session(day: 1, inHour: 13, outHour: 17)
        let dayTwo = TestData.session(day: 2)

        let total = OvertimeCalculator.aggregate(sessions: [dayOneA, dayOneB, dayTwo], settings: settings)

        XCTAssertEqual(total.gasAllowance, 70, accuracy: 0.001)
    }

    // MARK: - Unpaid breaks

    func testBreakDeductionRemovesOvertime() {
        var session = TestData.session(day: 1, inHour: 8, outHour: 17) // 9h on the clock
        session.breakMinutes = 30                                      // 8.5h paid

        let b = OvertimeCalculator.breakdown(for: session, settings: settings)

        XCTAssertEqual(b.totalHours, 8.5, accuracy: 0.001)
        XCTAssertEqual(b.regularHours, 8.5, accuracy: 0.001)
        XCTAssertEqual(b.ot125Hours, 0, accuracy: 0.001)
        XCTAssertEqual(b.grossPay, 850 + 35, accuracy: 0.01)
    }

    // MARK: - Rest-day / holiday rates

    func testRestDayTiers() {
        var session = TestData.session(day: 3, inHour: 6, outHour: 18) // 12h
        session.dayType = .restDay

        let b = OvertimeCalculator.breakdown(for: session, settings: settings)

        XCTAssertEqual(b.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(b.ot125Hours, 2.0, accuracy: 0.001)
        XCTAssertEqual(b.ot150Hours, 1.4, accuracy: 0.001)
        XCTAssertEqual(b.basePay, 8.6 * 100 * 1.5, accuracy: 0.01)   // 1290
        XCTAssertEqual(b.ot125Pay, 2.0 * 100 * 1.75, accuracy: 0.01) // 350
        XCTAssertEqual(b.ot150Pay, 1.4 * 100 * 2.0, accuracy: 0.01)  // 280
        XCTAssertEqual(b.grossPay, 1290 + 350 + 280 + 35, accuracy: 0.01)
    }

    func testHolidayPaysLikeRestDay() {
        var restDay = TestData.session(day: 3, inHour: 8, outHour: 18)
        restDay.dayType = .restDay
        var holiday = TestData.session(day: 3, inHour: 8, outHour: 18)
        holiday.dayType = .holiday

        let restPay = OvertimeCalculator.breakdown(for: restDay, settings: settings).grossPay
        let holidayPay = OvertimeCalculator.breakdown(for: holiday, settings: settings).grossPay

        XCTAssertEqual(restPay, holidayPay, accuracy: 0.001)
    }

    func testRegularDayUnchangedByPhase2Rules() {
        let session = TestData.session(day: 1, inHour: 6, outHour: 18) // 12h regular day

        let b = OvertimeCalculator.breakdown(for: session, settings: settings)

        // Matches the long-standing formula: 860 + 250 + 210 + 35
        XCTAssertEqual(b.grossPay, 1355, accuracy: 0.01)
    }

    // MARK: - Night shifts

    func testNightShiftOvertimeStartsAfterSevenHours() {
        let session = WorkSession(
            date: TestData.date(2026, 1, 1),
            clockIn: TestData.date(2026, 1, 1, 21),
            clockOut: TestData.date(2026, 1, 2, 6),
            isNightShift: true
        )

        let b = OvertimeCalculator.breakdown(for: session, settings: settings)

        XCTAssertEqual(b.totalHours, 9, accuracy: 0.001)
        XCTAssertEqual(b.regularHours, 7, accuracy: 0.001)
        XCTAssertEqual(b.ot125Hours, 2.0, accuracy: 0.001)
        XCTAssertEqual(b.ot150Hours, 0, accuracy: 0.001)
    }

    func testNightShiftAutoDetection() {
        // 21:00 → 06:00: 8h inside the 22:00–06:00 window
        XCTAssertTrue(WorkSession.qualifiesAsNightShift(
            clockIn: TestData.date(2026, 1, 1, 21),
            clockOut: TestData.date(2026, 1, 2, 6)
        ))
        // Ordinary day shift
        XCTAssertFalse(WorkSession.qualifiesAsNightShift(
            clockIn: TestData.date(2026, 1, 1, 8),
            clockOut: TestData.date(2026, 1, 1, 17)
        ))
        // 20:00 → 23:30: only 1.5h night time
        XCTAssertFalse(WorkSession.qualifiesAsNightShift(
            clockIn: TestData.date(2026, 1, 1, 20),
            clockOut: TestData.date(2026, 1, 1, 23, 30)
        ))
        // 20:00 → 00:30: 2.5h night time, crossing midnight
        XCTAssertTrue(WorkSession.qualifiesAsNightShift(
            clockIn: TestData.date(2026, 1, 1, 20),
            clockOut: TestData.date(2026, 1, 2, 0, 30)
        ))
    }

    // MARK: - Currency

    func testPayFormatterDiffersByCurrency() {
        let ils = PayFormatter.string(1234.5, currencyCode: "ILS")
        let usd = PayFormatter.string(1234.5, currencyCode: "USD")

        XCTAssertFalse(ils.isEmpty)
        XCTAssertNotEqual(ils, usd)
        XCTAssertTrue(ils.contains("234"))
    }

    func testBreakdownCarriesCurrencyCode() {
        var custom = TestData.settings()
        custom.currencyCode = "USD"

        let b = OvertimeCalculator.breakdown(totalHours: 8, settings: custom)

        XCTAssertEqual(b.currencyCode, "USD")
    }

    // MARK: - Codable back-compat

    func testLegacySessionJSONDecodesWithDefaults() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","date":"2026-01-01T00:00:00Z",\
        "clockIn":"2026-01-01T08:00:00Z","clockOut":"2026-01-01T16:00:00Z","isManualEntry":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(WorkSession.self, from: Data(json.utf8))

        XCTAssertEqual(session.breakMinutes, 0)
        XCTAssertEqual(session.dayType, .regular)
        XCTAssertFalse(session.isNightShift)
    }

    func testLegacySettingsJSONDecodesWithDefaults() throws {
        let json = """
        {"workplaceName":"X","workerFullName":"W","workerIDNumber":"1","employeeNumber":"2",\
        "hourlyRate":50,"dailyGasAllowance":35,"standardDayHours":8.6,"ot125HoursCap":2,\
        "locationRadiusMeters":150}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let settings = try decoder.decode(WorkplaceSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.restDayWeekday, 7)
        XCTAssertEqual(settings.defaultBreakMinutes, 0)
        XCTAssertEqual(settings.currencyCode, "ILS")
        XCTAssertEqual(settings.nightStandardDayHours, 7.0, accuracy: 0.001)
    }
}

@MainActor
final class PayRulesViewModelTests: XCTestCase {
    func testClockInAutoTagsRestDay() {
        let store = InMemoryStore()
        var settings = TestData.settings()
        settings.restDayWeekday = Calendar.current.component(.weekday, from: Date())
        store.storedSettings = settings
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        viewModel.clockIn()

        XCTAssertEqual(viewModel.sessions.first?.dayType, .restDay)
    }

    func testClockInOnOrdinaryWeekdayStaysRegular() {
        let store = InMemoryStore()
        var settings = TestData.settings()
        let todayWeekday = Calendar.current.component(.weekday, from: Date())
        settings.restDayWeekday = todayWeekday == 7 ? 1 : todayWeekday + 1
        store.storedSettings = settings
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        viewModel.clockIn()

        XCTAssertEqual(viewModel.sessions.first?.dayType, .regular)
    }
}
