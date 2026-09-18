import Foundation

/// Israeli statutory holidays — the ones that carry a 150%+ pay premium under
/// Israeli labor law (`DayType.holiday`). Purely informational display on
/// History's calendar; it does not change any shift's `DayType` automatically.
enum IsraeliHoliday: Equatable {
    case roshHashanah1
    case roshHashanah2
    case yomKippur
    case sukkot1
    case simchatTorah
    case pesach1
    case pesach7
    case shavuot
    case yomHaatzmaut

    /// Full name, for the selected-day detail label.
    var fullName: String {
        switch self {
        case .roshHashanah1, .roshHashanah2: return "ראש השנה"
        case .yomKippur: return "יום כיפור"
        case .sukkot1: return "סוכות"
        case .simchatTorah: return "שמחת תורה"
        case .pesach1: return "פסח"
        case .pesach7: return "שביעי של פסח"
        case .shavuot: return "שבועות"
        case .yomHaatzmaut: return "יום העצמאות"
        }
    }

    /// Short name, for the tight space inside a calendar day cell.
    var shortName: String {
        switch self {
        case .roshHashanah1, .roshHashanah2: return "ר\"ה"
        case .yomKippur: return "כיפור"
        case .sukkot1: return "סוכות"
        case .simchatTorah: return "ש. תורה"
        case .pesach1, .pesach7: return "פסח"
        case .shavuot: return "שבועות"
        case .yomHaatzmaut: return "עצמאות"
        }
    }
}

/// Computes the Gregorian date of each Israeli statutory holiday from the Hebrew
/// calendar, so dates are correct for any year without a hardcoded table that
/// would go stale. Uses `Calendar(identifier: .hebrew)` — the same calendar
/// engine iOS's own Calendar app uses.
///
/// Rosh Hashanah / Yom Kippur / Sukkot / Simchat Torah all fall within Tishrei,
/// which is always exactly 30 days regardless of the Hebrew year's length, so
/// they're computed as a simple day offset from 1 Tishrei — no leap-year
/// ambiguity possible. Pesach / Shavuot / Yom HaAtzmaut fall in Nisan/Sivan/Iyar,
/// several months later, where a leap year inserts an extra month (Adar I) ahead
/// of them and shifts their calendar month index by one — handled below by
/// checking the Hebrew year's actual month count rather than assuming it.
///
/// Note: Yom HaAtzmaut is officially shifted a day or two in some years to avoid
/// falling on a Friday/Saturday/Sunday, which this does not model — it always
/// resolves to the unshifted 5 Iyar. In years where the official observance
/// moves, this may be off by a day.
enum IsraeliHolidayCalendar {
    private static var hebrewCalendar: Calendar = {
        var calendar = Calendar(identifier: .hebrew)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem") ?? .current
        return calendar
    }()

    private static var cache: [Int: [Date: IsraeliHoliday]] = [:]

    /// The holiday on `date`, if any (compared by calendar day, in the current calendar).
    static func holiday(on date: Date, calendar: Calendar = .current) -> IsraeliHoliday? {
        let day = calendar.startOfDay(for: date)
        let gregorianYear = calendar.component(.year, from: day)
        var found: IsraeliHoliday?
        for year in [gregorianYear - 1, gregorianYear, gregorianYear + 1] {
            if let holiday = holidays(forGregorianYear: year)[day] {
                found = holiday
                break
            }
        }
        return found
    }

    /// Every statutory holiday whose Gregorian date could plausibly fall within
    /// `gregorianYear`, keyed by that date (start of day, in `Calendar.current`).
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
    /// Hashanah falls in autumn, so a Gregorian year's first months belong to the
    /// Hebrew year that started the previous autumn, while its last months may
    /// already belong to the next one.
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
        if let d = tishreiOffset(21) { results.append((d, .simchatTorah)) }
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
