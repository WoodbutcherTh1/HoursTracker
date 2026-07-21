import XCTest
@testable import HoursTrackerKit

final class ClockIntentDialogCopyTests: XCTestCase {
    func testEnglishClockedInIncludesTime() {
        XCTAssertEqual(
            ClockIntentDialogCopy.clockedIn(time: "7:20 AM", language: .english, isRestDay: false),
            "Clocked in at 7:20 AM"
        )
    }

    func testArabicRestDayClockedIn() {
        let message = ClockIntentDialogCopy.clockedIn(
            time: "07:20",
            language: .arabic,
            isRestDay: true
        )
        XCTAssertTrue(message.contains("يوم راحة"))
        XCTAssertTrue(message.contains("07:20"))
    }

    func testHebrewAlreadyInWithTime() {
        let message = ClockIntentDialogCopy.alreadyIn(existingTime: "08:15", language: .hebrew)
        XCTAssertTrue(message.contains("08:15"))
        XCTAssertTrue(message.contains("פתוחה"))
    }

    func testFormatTimeUsesLocale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 7, day: 21, hour: 7, minute: 20)
        )!
        let en = ClockIntentDialogCopy.formatTime(date, language: .english)
        XCTAssertFalse(en.isEmpty)
    }

    func testRejectedAlreadyInDoesNotImplySuccess() {
        // Guard: copy for already-in must not look like a successful clock-in.
        let message = ClockIntentDialogCopy.alreadyIn(existingTime: "07:20", language: .english)
        XCTAssertTrue(message.lowercased().contains("already"))
        XCTAssertFalse(message.lowercased().hasPrefix("clocked in at"))
    }
}
