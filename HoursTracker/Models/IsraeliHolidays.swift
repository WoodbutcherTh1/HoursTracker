import Foundation

/// A statutory Israeli holiday. `affectsPay` marks the ones that carry the
/// law-defined 150%+ pay premium (`DayType.holiday`) — only the actual Yom Tov
/// days observed in Israel (not Diaspora-only extra days like Pesach II/VIII,
/// and not Chol HaMoed mid-festival days, which are ordinary workdays).
/// Yom HaAtzmaut is a national holiday but isn't one of the religious chagim
/// this app's pay engine treats as a premium-pay day — it's shown on History's
/// calendar for awareness only and never affects a shift's `DayType`.
enum IsraeliHoliday: Equatable {
    case pesach1
    case pesach7
    case shavuot
    case roshHashanah1
    case roshHashanah2
    case yomKippur
    case sukkot1
    case shminiAtzeret
    case yomHaatzmaut

    var affectsPay: Bool {
        self != .yomHaatzmaut
    }

    /// English name, used in the Activity Log and anywhere the UI isn't Hebrew-specific.
    var englishName: String {
        switch self {
        case .pesach1: return "Pesach I"
        case .pesach7: return "Pesach VII"
        case .shavuot: return "Shavuot"
        case .roshHashanah1: return "Rosh Hashanah I"
        case .roshHashanah2: return "Rosh Hashanah II"
        case .yomKippur: return "Yom Kippur"
        case .sukkot1: return "Sukkot I"
        case .shminiAtzeret: return "Shemini Atzeret"
        case .yomHaatzmaut: return "Yom HaAtzmaut"
        }
    }

    /// Full Hebrew name, for History's selected-day banner.
    var hebrewName: String {
        switch self {
        case .pesach1, .pesach7: return "פסח"
        case .shavuot: return "שבועות"
        case .roshHashanah1, .roshHashanah2: return "ראש השנה"
        case .yomKippur: return "יום כיפור"
        case .sukkot1: return "סוכות"
        case .shminiAtzeret: return "שמחת תורה"
        case .yomHaatzmaut: return "יום העצמאות"
        }
    }

    /// Short Hebrew name, for a calendar day cell's tight space.
    var hebrewShortName: String {
        switch self {
        case .pesach1, .pesach7: return "פסח"
        case .shavuot: return "שבועות"
        case .roshHashanah1, .roshHashanah2: return "ר\"ה"
        case .yomKippur: return "כיפור"
        case .sukkot1: return "סוכות"
        case .shminiAtzeret: return "ש. תורה"
        case .yomHaatzmaut: return "עצמאות"
        }
    }
}

/// Bundled Israeli holiday calendar.
///
/// Rest days & holidays are law-defined paid days off. Instead of shipping a
/// static Gregorian table (which drifts every year), the mapping is computed
/// from the Hebrew calendar on every call — Foundation's `Calendar(identifier:
/// .hebrew)` converts the fixed Hebrew dates below into their correct Gregorian
/// dates for whatever year is queried, including leap years.
///
/// Foundation's Hebrew calendar numbers months civil-style, Tishrei = 1 (this
/// is ICU's `HebrewCalendar` convention, which Foundation wraps on Apple
/// platforms): Tishrei=1, Cheshvan=2, Kislev=3, Tevet=4, Shevat=5, Adar=6
/// (non-leap) / Adar I=6, Adar II=7 (leap), then Nisan/Iyar/Sivan/Tammuz/Av/Elul
/// shifted one month later in a leap year. An earlier version of this file
/// assumed the opposite (Nisan=1, Tishrei=7) and was computing every holiday's
/// date wrong as a result. Rosh Hashanah through Shemini Atzeret all fall
/// within Tishrei itself (always exactly 30 days, no leap-year variance), so
/// they're a simple day offset from 1 Tishrei; Pesach/Shavuot are in
/// Nisan/Sivan, past where a leap year inserts Adar I, so their month index
/// depends on whether the Hebrew year has 12 or 13 months.
enum IsraeliHolidayCalendar {
    private static let hebrewCalendar: Calendar = {
        var calendar = Calendar(identifier: .hebrew)
        calendar.timeZone = .current
        return calendar
    }()

    private static var cache: [Int: [Date: IsraeliHoliday]] = [:]

    /// The holiday observed on `date`, or nil when `date` is a regular workday.
    /// Includes Yom HaAtzmaut — use `isHoliday`/`holidayName` instead when only
    /// the pay-affecting holidays matter.
    static func holiday(on date: Date, calendar: Calendar = .current) -> IsraeliHoliday? {
        let day = calendar.startOfDay(for: date)
        let gregorianYear = calendar.component(.year, from: day)
        for year in [gregorianYear - 1, gregorianYear, gregorianYear + 1] {
            if let match = holidays(forGregorianYear: year)[day] {
                return match
            }
        }
        return nil
    }

    /// The pay-affecting holiday name observed on `date`, or nil otherwise.
    static func holidayName(on date: Date, calendar: Calendar = .current) -> String? {
        holiday(on: date, calendar: calendar).flatMap { $0.affectsPay ? $0.englishName : nil }
    }

    /// Convenience: true when `date` is a bundled, pay-affecting holiday.
    static func isHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        holiday(on: date, calendar: calendar)?.affectsPay == true
    }

    private static func holidays(forGregorianYear gregorianYear: Int) -> [Date: IsraeliHoliday] {
        if let cached = cache[gregorianYear] { return cached }
        var result: [Date: IsraeliHoliday] = [:]
        for hebrewYear in hebrewYears(overlapping: gregorianYear) {
            for (date, holiday) in datesForHebrewYear(hebrewYear) {
                result[Calendar.current.startOfDay(for: date)] = holiday
            }
        }
        cache[gregorianYear] = result
        return result
    }

    /// The Hebrew year(s) active at different points in `gregorianYear` — Rosh
    /// Hashanah falls in autumn, so a Gregorian year's first months belong to
    /// the Hebrew year that started the previous autumn, while its last months
    /// may already belong to the next one.
    private static func hebrewYears(overlapping gregorianYear: Int) -> Set<Int> {
        let gregorian = Calendar(identifier: .gregorian)
        var years = Set<Int>()
        for month in [1, 6, 12] {
            guard let date = gregorian.date(from: DateComponents(year: gregorianYear, month: month, day: 1))
            else { continue }
            years.insert(hebrewCalendar.component(.year, from: date))
        }
        return years
    }

    private static func datesForHebrewYear(_ year: Int) -> [(Date, IsraeliHoliday)] {
        guard let roshHashanah = hebrewDate(year: year, month: 1, day: 1) else { return [] }
        let isLeapYear = (hebrewCalendar.range(of: .month, in: .year, for: roshHashanah)?.count ?? 12) == 13
        // Civil month numbering (Tishrei = 1); a leap year inserts Adar I before
        // Adar II, pushing every month from Nisan onward one index later.
        let nisanMonth = isLeapYear ? 8 : 7
        let iyarMonth = isLeapYear ? 9 : 8
        let sivanMonth = isLeapYear ? 10 : 9

        func tishreiOffset(_ days: Int) -> Date? {
            Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: roshHashanah)
        }

        var results: [(Date, IsraeliHoliday)] = []
        if let d = tishreiOffset(0) { results.append((d, .roshHashanah1)) }
        if let d = tishreiOffset(1) { results.append((d, .roshHashanah2)) }
        if let d = tishreiOffset(9) { results.append((d, .yomKippur)) }
        if let d = tishreiOffset(14) { results.append((d, .sukkot1)) }
        if let d = tishreiOffset(21) { results.append((d, .shminiAtzeret)) }
        if let d = hebrewDate(year: year, month: nisanMonth, day: 15) { results.append((d, .pesach1)) }
        if let d = hebrewDate(year: year, month: nisanMonth, day: 21) { results.append((d, .pesach7)) }
        if let d = hebrewDate(year: year, month: sivanMonth, day: 6) { results.append((d, .shavuot)) }
        if let d = hebrewDate(year: year, month: iyarMonth, day: 5) { results.append((d, .yomHaatzmaut)) }
        return results
    }

    private static func hebrewDate(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return hebrewCalendar.date(from: components)
    }
}
