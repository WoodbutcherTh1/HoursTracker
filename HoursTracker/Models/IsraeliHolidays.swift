import Foundation

/// Bundled Israeli holiday calendar.
///
/// Rest days & holidays are law-defined paid days off. Instead of shipping a
/// static Gregorian table (which drifts every year), the mapping is computed
/// from the Hebrew calendar on every call — Foundation's `Calendar(identifier:
/// .hebrew)` converts the fixed Hebrew dates below into their correct Gregorian
/// dates for whatever year is queried, including leap years.
///
/// Only the main *paid rest days* observed in Israel are included (not
/// Chol HaMoed mid-festival days, which are ordinary workdays, and not
/// Purim, which is not a statutory rest day).
enum IsraeliHolidayCalendar {
    /// Fixed Hebrew-calendar dates: month/day in `Calendar(identifier: .hebrew)`
    /// numbering (Nisan = 1 … Elul = 6, Tishrei = 7, … Shevat = 11, Adar = 12;
    /// leap years add Adar I = 12 / Adar II = 13 — none of the listed holidays
    /// fall in Adar, so leap years need no special handling).
    private static let holidays: [(month: Int, day: Int, name: String)] = [
        (1, 15, "Pesach I"),
        (1, 16, "Pesach II"),
        (1, 21, "Pesach VII"),
        (1, 22, "Pesach VIII"),
        (3, 6, "Shavuot"),
        (7, 1, "Rosh Hashanah I"),
        (7, 2, "Rosh Hashanah II"),
        (7, 10, "Yom Kippur"),
        (7, 15, "Sukkot I"),
        (7, 22, "Shemini Atzeret"),
    ]

    private static let hebrewCalendar: Calendar = {
        var calendar = Calendar(identifier: .hebrew)
        calendar.timeZone = .current
        return calendar
    }()

    /// The holiday observed on `date`, or nil when `date` is a regular workday.
    static func holidayName(on date: Date, calendar: Calendar = .current) -> String? {
        // Normalize to the local start of day so time-of-day never matters.
        let day = calendar.startOfDay(for: date)
        let components = hebrewCalendar.dateComponents([.month, .day], from: day)
        guard let month = components.month, let dayOfMonth = components.day else { return nil }
        return holidays.first { $0.month == month && $0.day == dayOfMonth }?.name
    }

    /// Convenience: true when `date` is a bundled holiday.
    static func isHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        holidayName(on: date, calendar: calendar) != nil
    }
}