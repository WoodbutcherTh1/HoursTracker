import XCTest
@testable import HoursTracker

@MainActor
final class ShiftSummaryNotifierTests: XCTestCase {
    func testHoursTextIsHoursAndMinutes() {
        XCTAssertEqual(ShiftSummaryNotifier.hoursText(6.72), "6:43")
        XCTAssertEqual(ShiftSummaryNotifier.hoursText(0), "0:00")
        XCTAssertEqual(ShiftSummaryNotifier.hoursText(-1), "0:00")
        XCTAssertEqual(ShiftSummaryNotifier.hoursText(10.5), "10:30")
    }

    func testBodyLeavesPayOutWhenHidden() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        let clockIn = Date(timeIntervalSince1970: 7.5 * 3600)
        let clockOut = Date(timeIntervalSince1970: 14.2 * 3600)

        let hidden = ShiftSummaryNotifier.body(
            clockIn: clockIn, clockOut: clockOut, paidHours: 6.72, payText: nil, timeFormatter: formatter
        )
        XCTAssertTrue(hidden.hasPrefix("07:30–14:12 · "))
        XCTAssertTrue(hidden.contains("6:43"))
        XCTAssertEqual(hidden.components(separatedBy: " · ").count, 2)

        let shown = ShiftSummaryNotifier.body(
            clockIn: clockIn, clockOut: clockOut, paidHours: 6.72, payText: "≈ ₪337.63", timeFormatter: formatter
        )
        XCTAssertTrue(shown.hasSuffix(" · ≈ ₪337.63"))
    }
}
