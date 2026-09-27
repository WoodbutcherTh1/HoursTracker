import XCTest
@testable import HoursTracker

final class LivePayCurveTests: XCTestCase {
    private let start = TestData.date(2026, 3, 10, 8)

    private func curve(paused: Double? = nil) -> LivePayCurve {
        LivePayCurve(
            paidClockStart: start,
            pausedPaidSeconds: paused,
            points: [
                .init(paidSeconds: 0, gross: 0, net: 0),
                .init(paidSeconds: 3600, gross: 50, net: 40),
                .init(paidSeconds: 7200, gross: 110, net: 88)
            ],
            currencyCode: "ILS"
        )
    }

    func testInterpolatesBetweenSamples() {
        let pay = curve().pay(at: start.addingTimeInterval(1800))
        XCTAssertEqual(pay.gross, 25, accuracy: 0.001)
        XCTAssertEqual(pay.net, 20, accuracy: 0.001)
    }

    func testExactAtSamples() {
        XCTAssertEqual(curve().pay(at: start.addingTimeInterval(7200), net: false), 110, accuracy: 0.001)
    }

    func testExtendsAlongLastSlopePastTheEnd() {
        // Last segment: +60 gross per hour.
        XCTAssertEqual(curve().pay(at: start.addingTimeInterval(3 * 3600), net: false), 170, accuracy: 0.001)
    }

    func testClampsBeforeFirstSample() {
        XCTAssertEqual(curve().pay(at: start.addingTimeInterval(-600), net: false), 0, accuracy: 0.001)
    }

    func testPausedCurveStandsStill() {
        let paused = curve(paused: 3600)
        XCTAssertEqual(paused.paidHours(at: start.addingTimeInterval(5 * 3600)), 1, accuracy: 0.001)
        XCTAssertEqual(paused.pay(at: start.addingTimeInterval(5 * 3600), net: true), 40, accuracy: 0.001)
    }

    func testRoundTripsThroughJSON() throws {
        let original = curve(paused: 120)
        let decoded = try JSONDecoder().decode(LivePayCurve.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}

@MainActor
final class LivePayCurveBuilderTests: XCTestCase {
    private func makeViewModel(open session: WorkSession, settings: WorkplaceSettings) -> AppViewModel {
        let store = InMemoryStore()
        store.storedSessions = [session]
        store.storedSettings = settings
        return AppViewModel(store: store, locationManager: MockLocationReminderManager())
    }

    private var settings: WorkplaceSettings {
        var settings = WorkplaceSettings.default
        settings.hourlyRate = 50
        return settings
    }

    /// The curve must agree with pricing the shift directly — that's what makes every
    /// surface show the same figure as Home.
    func testCurveMatchesDirectPricingAtSamples() {
        let now = Date()
        let clockIn = now.addingTimeInterval(-2 * 3600)
        let session = WorkSession(date: Calendar.current.startOfDay(for: clockIn), clockIn: clockIn)
        let viewModel = makeViewModel(open: session, settings: settings)

        let curve = viewModel.makeLivePayCurve(for: session, now: now)
        for hoursAhead in [0.0, 1.0, 7.0] {
            let date = now.addingTimeInterval(hoursAhead * 3600)
            let direct = viewModel.liveBreakdown(for: session, at: date)
            XCTAssertEqual(curve.pay(at: date, net: false), direct.grossPay, accuracy: 0.01, "at +\(hoursAhead)h")
            XCTAssertEqual(curve.pay(at: date, net: true), direct.netPay, accuracy: 0.01, "at +\(hoursAhead)h")
        }
        XCTAssertEqual(curve.sessionID, session.id)
        XCTAssertFalse(curve.isPaused)
    }

    func testUnpaidBreakPausesTheCurve() {
        let now = Date()
        let clockIn = now.addingTimeInterval(-3 * 3600)
        var session = WorkSession(date: Calendar.current.startOfDay(for: clockIn), clockIn: clockIn)
        session.startBreak(at: now.addingTimeInterval(-600))
        let viewModel = makeViewModel(open: session, settings: settings)

        let curve = viewModel.makeLivePayCurve(for: session, now: now)
        XCTAssertTrue(curve.isPaused)
        XCTAssertEqual(curve.paidHours(at: now.addingTimeInterval(3600)), curve.paidHours(at: now), accuracy: 0.001)
        XCTAssertEqual(
            curve.pay(at: now.addingTimeInterval(3600), net: false),
            curve.pay(at: now, net: false),
            accuracy: 0.001
        )
    }

    func testPaidBreakKeepsTheCurveRunning() {
        let now = Date()
        let clockIn = now.addingTimeInterval(-3 * 3600)
        var session = WorkSession(date: Calendar.current.startOfDay(for: clockIn), clockIn: clockIn)
        session.startBreak(at: now.addingTimeInterval(-600))
        var paid = settings
        paid.breaksArePaid = true
        let viewModel = makeViewModel(open: session, settings: paid)

        let curve = viewModel.makeLivePayCurve(for: session, now: now)
        XCTAssertFalse(curve.isPaused)
        XCTAssertGreaterThan(curve.pay(at: now.addingTimeInterval(3600), net: false), curve.pay(at: now, net: false))
    }
}
