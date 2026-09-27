import XCTest
@testable import HoursTracker

@MainActor
final class DaySummaryTests: XCTestCase {
    // MARK: Shabbat / rest-day shifts

    /// The engine keeps rest-day hours in its "regular" bucket but pays them at 1.5×,
    /// so the display must read the day type: all 8 hours show as one 150% tier, in
    /// orange, and never as "Regular 100%".
    func testShabbatShiftShowsAllHoursAt150Percent() {
        let settings = TestData.settings(hourlyRate: 50)
        // 3 Jan 2026 is a Saturday.
        let shabbat = TestData.session(day: 3, inHour: 8, outHour: 16, dayType: .restDay)
        let breakdown = OvertimeCalculator.breakdown(for: shabbat, in: [shabbat], settings: settings)

        // What the engine does (unchanged): base bucket, paid at 150%.
        XCTAssertEqual(breakdown.totalHours, 8, accuracy: 0.001)
        XCTAssertEqual(breakdown.basePay, 8 * 50 * 1.5, accuracy: 0.01)

        // What the Pay Card shows.
        let tiers = PayTier.tiers(for: breakdown, dayType: shabbat.dayType)
        XCTAssertEqual(tiers.map(\.percent), [150])
        XCTAssertEqual(tiers.first?.hours ?? 0, breakdown.totalHours, accuracy: 0.001)
        XCTAssertEqual(PayTier.dominantPercent(tiers), 150)
        XCTAssertEqual(PayTier.tone(percent: 150), .orange, "Shabbat glow must be orange")
        XCTAssertFalse(DaySummarySheet.tierLabel(tiers[0], dayType: .restDay).contains("100"))
    }

    func testLongShabbatShiftClimbsTo175And200() {
        let settings = TestData.settings(hourlyRate: 50)
        let shabbat = TestData.session(day: 3, inHour: 6, outHour: 17, dayType: .restDay) // 11h
        let breakdown = OvertimeCalculator.breakdown(for: shabbat, in: [shabbat], settings: settings)
        let tiers = PayTier.tiers(for: breakdown, dayType: .restDay)
        XCTAssertEqual(tiers.map(\.percent), [150, 175, 200])
        XCTAssertEqual(PayTier.dominantPercent(tiers), 200)
        XCTAssertEqual(PayTier.tone(percent: 200), .orange)
    }

    func testRegularDayTiersAndGlow() {
        let settings = TestData.settings(hourlyRate: 50)
        let tenHours = TestData.session(day: 5, inHour: 7, outHour: 17)
        let breakdown = OvertimeCalculator.breakdown(for: tenHours, in: [tenHours], settings: settings)
        let tiers = PayTier.tiers(for: breakdown, dayType: .regular)
        XCTAssertEqual(tiers.map(\.percent), [100, 125])
        XCTAssertEqual(PayTier.tone(percent: PayTier.dominantPercent(tiers) ?? 100), .gold)
        XCTAssertEqual(PayTier.tone(percent: 100), .accent)
    }

    /// Net mode shows each line's proportional share; together they add up to the net.
    func testNetSharesAddUpToTheNetHero() {
        let settings = TestData.settings(hourlyRate: 50)
        let session = TestData.session(day: 5, inHour: 6, outHour: 18) // 12h: all three tiers
        let breakdown = OvertimeCalculator.breakdown(for: session, in: [session], settings: settings)
        let tiers = PayTier.tiers(for: breakdown, dayType: .regular)
        let tierNet = tiers.reduce(0.0) {
            $0 + $1.approximateNet(dayGross: breakdown.grossPay, dayNet: breakdown.netPay)
        }
        let gasNet = PayTier.netShare(of: breakdown.gasAllowance, in: breakdown)
        XCTAssertEqual(tierNet + gasNet, breakdown.netPay, accuracy: 0.01)
    }

    // MARK: Live surfaces debounce

    /// Two quick gross/net taps send one update, carrying the last choice.
    func testQuickRepeatedRefreshesSendOneUpdateWithTheLastValue() async throws {
        let key = "homePayDisplayMode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        let viewModel = AppViewModel(store: InMemoryStore(), locationManager: MockLocationReminderManager())
        let before = viewModel.liveSurfacesPushCount

        UserDefaults.standard.set(PayDisplayMode.gross.rawValue, forKey: key)
        viewModel.refreshLiveSurfaces()
        UserDefaults.standard.set(PayDisplayMode.net.rawValue, forKey: key)
        viewModel.refreshLiveSurfaces()

        try await Task.sleep(for: .milliseconds(700))

        XCTAssertEqual(viewModel.liveSurfacesPushCount, before + 1, "Debounce should collapse the two taps")
        XCTAssertEqual(viewModel.lastLiveSurfacesShowsNet, true, "The update must carry the last choice (net)")
    }
}
