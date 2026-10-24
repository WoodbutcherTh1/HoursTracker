import XCTest
@testable import HoursTracker

final class HolidayCustomizationTests: XCTestCase {
    private let calendar = Calendar.current

    /// Some bundled holiday in 2026, found from the calendar itself so the test
    /// doesn't hard-code Hebrew-calendar dates.
    private var bundled: (date: Date, holiday: IsraeliHoliday) {
        IsraeliHolidayCalendar.bundledHolidays(inYear: 2026, calendar: calendar).first { $0.holiday.affectsPay }!
    }

    func testBundledHolidayUnchangedByDefault() {
        let day = bundled.date
        XCTAssertTrue(IsraeliHolidayCalendar.isHoliday(day, calendar: calendar, customization: HolidayCustomization()))
    }

    func testHiddenBundledHolidayIsNotAHoliday() {
        let day = bundled.date
        let customization = HolidayCustomization(hiddenDates: [day])
        XCTAssertNil(IsraeliHolidayCalendar.resolved(on: day, calendar: calendar, customization: customization))
        XCTAssertFalse(IsraeliHolidayCalendar.isHoliday(day, calendar: calendar, customization: customization))
    }

    func testCustomHolidayAddedAndRenamed() {
        let day = TestData.date(2026, 1, 14) // no statutory holiday in January
        let customization = HolidayCustomization(custom: [CustomHoliday(date: day, name: "Company day")])
        let resolved = IsraeliHolidayCalendar.resolved(on: day, calendar: calendar, customization: customization)
        XCTAssertEqual(resolved?.englishName, "Company day")
        XCTAssertEqual(resolved?.isCustom, true)
        XCTAssertTrue(IsraeliHolidayCalendar.isHoliday(day, calendar: calendar, customization: customization))
    }

    func testCustomHolidayWithoutPayRateDoesNotAffectPay() {
        let day = TestData.date(2026, 1, 14)
        let customization = HolidayCustomization(custom: [CustomHoliday(date: day, name: "Fun day", affectsPay: false)])
        XCTAssertFalse(IsraeliHolidayCalendar.isHoliday(day, calendar: calendar, customization: customization))
    }

    func testCustomizationSurvivesSettingsRoundTripAndOldSettingsDecode() throws {
        var settings = WorkplaceSettings.default
        settings.holidayCustomization = HolidayCustomization(
            custom: [CustomHoliday(date: TestData.date(2026, 1, 14), name: "Company day")],
            hiddenDates: [TestData.date(2026, 1, 20)]
        )
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(WorkplaceSettings.self, from: data).holidayCustomization, settings.holidayCustomization)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "holidayCustomization")
        let old = try JSONDecoder().decode(WorkplaceSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.holidayCustomization.isEmpty)
    }
}
