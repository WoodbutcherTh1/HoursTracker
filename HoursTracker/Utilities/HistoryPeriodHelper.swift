import Foundation

enum PayDisplayMode: String, CaseIterable, Identifiable {
    case net
    case gross

    var id: String { rawValue }

    var title: String {
        switch self {
        case .net:
            return String(localized: "pay.net", defaultValue: "Net (נטו)")
        case .gross:
            return String(localized: "pay.gross", defaultValue: "Gross (ברוטו)")
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

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }

    var days: [Date] {
        HistoryPeriodHelper.days(from: start, through: end)
    }
}

enum HistoryPeriodHelper {
    /// Clamp to 1...28 so every month has a valid start day.
    static func normalizedStartDay(_ day: Int) -> Int {
        min(max(day, 1), 28)
    }

    static func monthTitle(for date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    static func payrollPeriodTitle(for period: PayrollPeriod, locale: Locale = .current) -> String {
        monthTitle(for: period.labelMonth, locale: locale)
    }

    /// Payroll cycle whose start falls in the same calendar month as `monthAnchor`.
    /// Example: startDay=10, July anchor → Jul 10 … Aug 9.
    static func payrollPeriod(
        forMonthAnchor monthAnchor: Date,
        startDay: Int,
        calendar: Calendar = .current
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
        calendar: Calendar = .current
    ) -> PayrollPeriod {
        let day = normalizedStartDay(startDay)
        let dateDay = calendar.component(.day, from: date)
        var anchor = date
        if dateDay < day {
            anchor = calendar.date(byAdding: .month, value: -1, to: date) ?? date
        }
        return payrollPeriod(forMonthAnchor: anchor, startDay: day, calendar: calendar)
    }

    static func shiftPayrollAnchor(_ anchor: Date, by months: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: months, to: anchor) ?? anchor
    }

    static func days(from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
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

    static func daysInMonth(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        else { return [] }

        return range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        }
    }

    static func shiftMonth(_ date: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: value, to: date) ?? date
    }

    static func formatHoursClock(_ hours: Double) -> String {
        let totalSeconds = Int((hours * 3600).rounded())
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    static func weekdayLetter(for date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date)
    }

    static func shortRangeLabel(for period: PayrollPeriod, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("dd/MM")
        return "\(f.string(from: period.start)) – \(f.string(from: period.end))"
    }
}
