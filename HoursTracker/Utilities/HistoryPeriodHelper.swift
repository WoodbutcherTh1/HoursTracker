import Foundation

enum PayDisplayMode: String, CaseIterable, Identifiable {
    case net
    case gross

    var id: String { rawValue }

    var title: String {
        switch self {
        case .net:
            return AppLocale.tr("pay.net")
        case .gross:
            return AppLocale.tr("pay.gross")
        }
    }
}

struct PayrollPeriod: Equatable {
    /// Inclusive start of the payroll window (start of day).
    let start: Date
    /// Inclusive end of the payroll window (start of day for the last day).
    let end: Date
    /// Month used for the header label (the month that contains `start`).
    let labelMonth: Date

    func contains(_ date: Date, calendar: Calendar = AppLocale.calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }

    var days: [Date] {
        HistoryPeriodHelper.days(from: start, through: end)
    }
}

/// One day cell in a padded payroll week row.
struct PayrollWeekDay: Equatable, Identifiable {
    let date: Date
    /// `false` for leading/trailing padding outside the payroll window.
    let isInPeriod: Bool
    var id: Date { date }
}

/// A full calendar week (always 7 days) covering part of a payroll period.
struct PayrollWeek: Equatable, Identifiable {
    let days: [PayrollWeekDay]
    var id: Date { days.first?.date ?? .distantPast }
}

enum HistoryPeriodHelper {
    /// Clamp to 1...28 so every month has a valid start day.
    static func normalizedStartDay(_ day: Int) -> Int {
        min(max(day, 1), 28)
    }

    static func monthTitle(for date: Date, locale: Locale = AppLocale.resolvedLocale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    static func payrollPeriodTitle(for period: PayrollPeriod, locale: Locale = AppLocale.resolvedLocale) -> String {
        monthTitle(for: period.labelMonth, locale: locale)
    }

    /// Payroll cycle whose start falls in the same calendar month as `monthAnchor`.
    /// Example: startDay=10, July anchor → Jul 10 … Aug 9.
    static func payrollPeriod(
        forMonthAnchor monthAnchor: Date,
        startDay: Int,
        calendar: Calendar = AppLocale.calendar
    ) -> PayrollPeriod {
        let day = normalizedStartDay(startDay)
        var startComponents = calendar.dateComponents([.year, .month], from: monthAnchor)
        startComponents.day = day
        let start = calendar.startOfDay(for: calendar.date(from: startComponents) ?? monthAnchor)

        guard let nextStart = calendar.date(byAdding: .month, value: 1, to: start),
              let end = calendar.date(byAdding: .day, value: -1, to: nextStart)
        else {
            return PayrollPeriod(start: start, end: start, labelMonth: start)
        }

        return PayrollPeriod(
            start: start,
            end: calendar.startOfDay(for: end),
            labelMonth: start
        )
    }

    /// The payroll period that contains a given date.
    static func payrollPeriod(
        containing date: Date,
        startDay: Int,
        calendar: Calendar = AppLocale.calendar
    ) -> PayrollPeriod {
        let day = normalizedStartDay(startDay)
        let dateDay = calendar.component(.day, from: date)
        var anchor = date
        if dateDay < day {
            anchor = calendar.date(byAdding: .month, value: -1, to: date) ?? date
        }
        return payrollPeriod(forMonthAnchor: anchor, startDay: day, calendar: calendar)
    }

    static func shiftPayrollAnchor(_ anchor: Date, by months: Int, calendar: Calendar = AppLocale.calendar) -> Date {
        calendar.date(byAdding: .month, value: months, to: anchor) ?? anchor
    }

    static func days(from start: Date, through end: Date, calendar: Calendar = AppLocale.calendar) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard startDay <= endDay else { return [startDay] }

        var result: [Date] = []
        var cursor = startDay
        while cursor <= endDay {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Start of the calendar week that contains `date` (honors `calendar.firstWeekday`).
    static func startOfWeek(containing date: Date, calendar: Calendar = AppLocale.calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: day) ?? day
    }

    /// Split a payroll period into padded week rows (always 7 columns).
    /// Days before `period.start` / after `period.end` are included with `isInPeriod == false`.
    static func weekRows(
        for period: PayrollPeriod,
        calendar: Calendar = AppLocale.calendar
    ) -> [PayrollWeek] {
        let periodDays = period.days
        guard let first = periodDays.first, let last = periodDays.last else { return [] }

        let gridStart = startOfWeek(containing: first, calendar: calendar)
        let lastWeekStart = startOfWeek(containing: last, calendar: calendar)
        guard let gridEnd = calendar.date(byAdding: .day, value: 6, to: lastWeekStart) else { return [] }

        var weeks: [PayrollWeek] = []
        var cursor = gridStart
        while cursor <= gridEnd {
            let days: [PayrollWeekDay] = (0..<7).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: cursor) else { return nil }
                let start = calendar.startOfDay(for: date)
                return PayrollWeekDay(
                    date: start,
                    isInPeriod: period.contains(start, calendar: calendar)
                )
            }
            guard days.count == 7 else { break }
            weeks.append(PayrollWeek(days: days))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    /// Index of the week row that contains `day`, if any.
    static func weekIndex(
        containing day: Date,
        in weeks: [PayrollWeek],
        calendar: Calendar = AppLocale.calendar
    ) -> Int? {
        let target = calendar.startOfDay(for: day)
        return weeks.firstIndex { week in
            week.days.contains { calendar.isDate($0.date, inSameDayAs: target) }
        }
    }

    static func daysInMonth(containing date: Date, calendar: Calendar = AppLocale.calendar) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        else { return [] }

        return range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        }
    }

    static func shiftMonth(_ date: Date, by value: Int, calendar: Calendar = AppLocale.calendar) -> Date {
        calendar.date(byAdding: .month, value: value, to: date) ?? date
    }

    static func formatHoursClock(_ hours: Double) -> String {
        let totalSeconds = Int((hours * 3600).rounded())
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    static func weekdayLetter(for date: Date, locale: Locale = AppLocale.resolvedLocale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date)
    }

    static func shortRangeLabel(for period: PayrollPeriod, locale: Locale = AppLocale.resolvedLocale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = Calendar(identifier: .gregorian)
        f.setLocalizedDateFormatFromTemplate("dd/MM")
        return "\(f.string(from: period.start)) – \(f.string(from: period.end))"
    }

    /// Per-day worked hours for the calendar week containing `date` (7 values, week-start first).
    /// Only completed sessions (`clockOut != nil`) contribute; open shifts are ignored.
    static func dailyHoursForWeek(
        containing date: Date,
        sessions: [WorkSession],
        calendar: Calendar = AppLocale.calendar
    ) -> [Double] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 0)
        let completed = sessions.filter { $0.clockOut != nil }
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return 0 }
            return completed
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.totalHours }
        }
    }

    /// Normalize daily hours to 0...1 chart heights.
    /// Zero-hour days stay at 0 (flat). Non-zero days scale to the week's max,
    /// with a small floor so short days remain visible next to long ones.
    static func normalizedDayHeights(
        _ dailyHours: [Double],
        minimumNonZero: Double = 0.12
    ) -> [Double] {
        let hours = dailyHours.isEmpty ? Array(repeating: 0.0, count: 7) : dailyHours
        let peak = hours.max() ?? 0
        guard peak > 0.01 else {
            return Array(repeating: 0, count: hours.count)
        }
        return hours.map { value in
            guard value > 0.01 else { return 0 }
            return min(1, max(minimumNonZero, value / peak))
        }
    }
}
