import XCTest
@testable import HoursTrackerKit

final class PhoneScreenshotDemoDataTests: XCTestCase {
    func testDemoHasNoOpenSessionAndNoNationalID() {
        let demo = PhoneScreenshotDemoData.makeDemo(
            now: Date(timeIntervalSince1970: 1_784_400_000) // fixed
        )
        XCTAssertFalse(demo.sessions.contains(where: \.isOpen))
        XCTAssertGreaterThanOrEqual(demo.sessions.count, 20)
        XCTAssertTrue(demo.sessions.contains(where: \.isNightShift))
        XCTAssertTrue(demo.sessions.contains(where: { $0.dayType == .restDay }))
        XCTAssertTrue(demo.settings.workerIDNumber.isEmpty)
        XCTAssertFalse(demo.settings.workerFullName.isEmpty)
        XCTAssertNil(demo.settings.locationLatitude)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_784_400_000))
        let primary = cal.date(byAdding: .day, value: -1, to: today)!
        let primaryCount = demo.sessions.filter { cal.isDate($0.date, inSameDayAs: primary) }.count
        XCTAssertGreaterThanOrEqual(primaryCount, 3)

        let oldest = demo.sessions.map(\.date).min()!
        let spanDays = cal.dateComponents([.day], from: oldest, to: today).day ?? 0
        XCTAssertGreaterThanOrEqual(spanDays, 14)
    }

    func testGuestNamesByLanguage() {
        XCTAssertEqual(PhoneScreenshotDemoData.guestName(for: .hebrew), "אורח")
        XCTAssertEqual(PhoneScreenshotDemoData.guestName(for: .english), "Guest")
        XCTAssertEqual(PhoneScreenshotDemoData.guestName(for: .arabic), "ضيف")
    }
}
