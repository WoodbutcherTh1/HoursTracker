import XCTest
@testable import HoursTracker

/// The engine is what stops the assistant hallucinating: whatever plan comes back from
/// the model, every figure the user reads has to come from their own sessions or from
/// `OvertimeCalculator`. These tests pin that down.
final class AssistantEngineTests: XCTestCase {
    private var calendar: Calendar!
    private var settings: WorkplaceSettings!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        settings = .default
        settings.hourlyRate = 50
    }

    private func date(month: Int = 8, day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func session(month: Int = 8, day: Int, startHour: Int = 9, hours: Double = 8) -> WorkSession {
        let clockIn = date(month: month, day: day, hour: startHour)
        return WorkSession(
            date: calendar.startOfDay(for: clockIn),
            clockIn: clockIn,
            clockOut: clockIn.addingTimeInterval(hours * 3600)
        )
    }

    private func engine(_ sessions: [WorkSession]) -> AssistantEngine {
        AssistantEngine(
            settings: settings,
            sessions: sessions,
            calendar: calendar,
            now: date(day: 21)
        )
    }

    // MARK: - Scope boundary

    func testOutOfScopeIsAnsweredFromTheAppNotTheModel() {
        let answer = engine([]).resolve(plan: AssistantPlan(action: .outOfScope))

        XCTAssertEqual(answer.headline, L10n.assistantOutOfScope)
        XCTAssertTrue(answer.rows.isEmpty)
        XCTAssertNil(answer.attachment)
    }

    /// A model asked about a month with nothing recorded must produce "no data", never a
    /// plausible-looking total.
    func testAskingAboutAMonthWithNoDataReportsNoData() {
        let answer = engine([session(day: 3)]).resolve(
            plan: AssistantPlan(action: .aggregatePay, filters: AssistantFilters(month: "2026-02"))
        )

        XCTAssertEqual(answer.headline, L10n.assistantNoData)
        XCTAssertTrue(answer.rows.isEmpty)
    }

    // MARK: - Grounded figures

    func testHoursSummaryMatchesTheOvertimeEngineExactly() {
        let sessions = [session(day: 3, hours: 12), session(day: 4, hours: 6)]
        let expected = OvertimeCalculator.aggregate(sessions: sessions, settings: settings)

        let answer = engine(sessions).resolve(
            plan: AssistantPlan(action: .summarizeHours, filters: AssistantFilters(month: "2026-08"))
        )

        XCTAssertTrue(
            answer.headline.contains(HistoryPeriodHelper.formatHoursClock(expected.totalHours))
        )
        XCTAssertEqual(
            answer.rows.map(\.value),
            [
                HistoryPeriodHelper.formatHoursClock(expected.regularHours),
                HistoryPeriodHelper.formatHoursClock(expected.ot125Hours),
                HistoryPeriodHelper.formatHoursClock(expected.ot150Hours)
            ]
        )
    }

    func testPayUsesTheRequestedModeAndTheAppsOwnFormatting() {
        let sessions = [session(day: 3, hours: 9)]
        let expected = OvertimeCalculator.aggregate(sessions: sessions, settings: settings)

        let gross = engine(sessions).resolve(
            plan: AssistantPlan(
                action: .aggregatePay,
                filters: AssistantFilters(month: "2026-08"),
                payMode: .gross
            )
        )
        XCTAssertTrue(gross.headline.contains(expected.formattedGrossPay))

        let net = engine(sessions).resolve(
            plan: AssistantPlan(
                action: .aggregatePay,
                filters: AssistantFilters(month: "2026-08"),
                payMode: .net
            )
        )
        XCTAssertTrue(net.headline.contains(expected.formattedNetPay))
    }

    // MARK: - Filter composition

    func testFiltersCompose() {
        let sessions = [
            session(day: 3, startHour: 8, hours: 12),   // early, long
            session(day: 4, startHour: 18, hours: 12),  // late, long
            session(day: 5, startHour: 18, hours: 4),   // late, short
            session(month: 7, day: 4, startHour: 18, hours: 12) // wrong month
        ]

        let selection = engine(sessions).select(
            with: AssistantFilters(
                month: "2026-08",
                clockInAfter: "17:00",
                overtimeTier: .ot125
            )
        )

        XCTAssertEqual(selection.sessions.count, 1)
        XCTAssertEqual(selection.sessions.first?.id, sessions[1].id)
        XCTAssertFalse(selection.description.isEmpty, "the answer must be able to state its scope")
    }

    func testOpenShiftsAreNeverCounted() {
        let clockIn = date(day: 20, hour: 9)
        let open = WorkSession(date: calendar.startOfDay(for: clockIn), clockIn: clockIn, clockOut: nil)

        let selection = engine([session(day: 3), open]).select(with: AssistantFilters())

        XCTAssertEqual(selection.sessions.count, 1)
    }

    func testNoFiltersMeansAllTimeAndSaysSo() {
        let selection = engine([session(month: 3, day: 3), session(month: 8, day: 3)])
            .select(with: AssistantFilters())

        XCTAssertEqual(selection.sessions.count, 2)
        XCTAssertEqual(selection.description, L10n.assistantScopeAllTime)
    }

    // MARK: - Date parsing

    func testMonthFilterResolvesToTheWholeCalendarMonth() {
        let interval = engine([]).resolvedInterval(from: AssistantFilters(month: "2026-02"))

        XCTAssertNotNil(interval)
        XCTAssertEqual(calendar.component(.day, from: interval!.start), 1)
        XCTAssertEqual(calendar.component(.day, from: interval!.end), 28)
    }

    func testExplicitRangeWins() {
        let interval = engine([]).resolvedInterval(
            from: AssistantFilters(month: "2026-02", startDate: "2026-08-01", endDate: "2026-08-10")
        )

        XCTAssertNotNil(interval)
        XCTAssertEqual(calendar.component(.month, from: interval!.start), 8)
        XCTAssertEqual(calendar.component(.day, from: interval!.end), 10)
    }

    func testUnparseableDatesFallBackToAllTimeRatherThanAWrongWindow() {
        XCTAssertNil(engine([]).resolvedInterval(from: AssistantFilters(month: "last month")))
    }

    // MARK: - Days off

    func testDaysWithoutSessionsReportsNothingWhenEveryDayWasWorked() {
        let worked = (1...21).map { session(day: $0) }

        let answer = engine(worked).resolve(
            plan: AssistantPlan(
                action: .listDaysWithoutSessions,
                filters: AssistantFilters(month: "2026-08")
            )
        )

        XCTAssertEqual(answer.headline, L10n.assistantNoDaysOff)
    }
}
