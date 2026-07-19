import XCTest
@testable import HoursTrackerKit

final class PhoneScreenshotDemoDataTests: XCTestCase {
    func testDemoHasNoOpenSessionAndNoNationalID() {
        let demo = PhoneScreenshotDemoData.makeDemo(
            now: Date(timeIntervalSince1970: 1_784_400_000) // fixed
        )
        XCTAssertFalse(demo.sessions.contains(where: \.isOpen))
        XCTAssertGreaterThanOrEqual(demo.sessions.count, 10)
        XCTAssertTrue(demo.settings.workerIDNumber.isEmpty)
        XCTAssertFalse(demo.settings.workerFullName.isEmpty)
        XCTAssertNil(demo.settings.locationLatitude)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_784_400_000))
        let primary = cal.date(byAdding: .day, value: -1, to: today)!
        let primaryCount = demo.sessions.filter { cal.isDate($0.date, inSameDayAs: primary) }.count
        XCTAssertGreaterThanOrEqual(primaryCount, 3)
    }

    func testGuestNamesByLanguage() {
        XCTAssertEqual(PhoneScreenshotDemoData.guestName(for: .hebrew), "אורח")
        XCTAssertEqual(PhoneScreenshotDemoData.guestName(for: .english), "Guest")
        XCTAssertEqual(PhoneScreenshotDemoData.guestName(for: .arabic), "ضيف")
    }
}
