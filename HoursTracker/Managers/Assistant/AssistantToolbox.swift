import Foundation

/// The assistant's data tools: ordinary Swift functions over the user's real sessions.
///
/// Nothing in here calls a model, and the model never runs any of it — it only names
/// which of these to apply and with what arguments (see `AssistantPlan`). Every number
/// an answer contains is produced here or by `OvertimeCalculator`, which is why the
/// assistant cannot invent an hour, a date, or a shekel it doesn't have data for.
///
/// The filters compose: each takes sessions and returns sessions, so "shifts in July that
/// started after 17:00 and ran into 150%" is three of them chained, not a special case.
enum AssistantToolbox {
    // MARK: - Filters

    /// Sessions whose day falls within `start...end`, inclusive at both ends.
    static func filterSessionsByDateRange(
        _ sessions: [WorkSession],
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> [WorkSession] {
        let lower = calendar.startOfDay(for: min(start, end))
        let upper = calendar.startOfDay(for: max(start, end))
        return sessions.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= lower && day <= upper
        }
    }

    /// Sessions clocked in at or after a time of day, e.g. "evening shifts" at 17:00.
    /// Compared against wall-clock time, so it works across any number of dates.
    static func filterSessionsByClockInAfter(
        _ sessions: [WorkSession],
        minutesFromMidnight threshold: Int,
        calendar: Calendar = .current
    ) -> [WorkSession] {
        sessions.filter { minutesFromMidnight(for: $0.clockIn, calendar: calendar) >= threshold }
    }

    /// Sessions clocked in strictly before a time of day.
    static func filterSessionsByClockInBefore(
        _ sessions: [WorkSession],
        minutesFromMidnight threshold: Int,
        calendar: Calendar = .current
    ) -> [WorkSession] {
        sessions.filter { minutesFromMidnight(for: $0.clockIn, calendar: calendar) < threshold }
    }

    /// Sessions that actually earned hours in the requested tier, decided by
    /// `OvertimeCalculator` rather than by a rule of thumb about shift length — so
    /// rest-day and holiday premiums, night-shift thresholds, and same-day overtime
    /// sharing are all accounted for.
    static func filterSessionsByOvertimeTier(
        _ sessions: [WorkSession],
        tier: AssistantOvertimeTier,
        settings: WorkplaceSettings,
        calendar: Calendar = .current
    ) -> [WorkSession] {
        let priced = OvertimeCalculator.dayAwareBreakdowns(
            sessions: sessions.filter { $0.clockOut != nil },
            settings: settings,
            calendar: calendar
        )
        let matching = priced.filter { entry in
            switch tier {
            case .regular: return entry.breakdown.regularHours > 0
            case .ot125: return entry.breakdown.ot125Hours > 0
            case .ot150: return entry.breakdown.ot150Hours > 0
            }
        }
        let ids = Set(matching.map { $0.session.id })
        return sessions.filter { ids.contains($0.id) }
    }

    static func filterSessionsByDayType(
        _ sessions: [WorkSession],
        dayType: DayType
    ) -> [WorkSession] {
        sessions.filter { $0.dayType == dayType }
    }

    /// Days in `month`'s calendar month with no completed session — "the days I didn't
    /// work". Future days are excluded when the month is the current one: a day that
    /// hasn't happened yet isn't a day off.
    static func findDaysWithoutSessions(
        month: Date,
        sessions: [WorkSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        let allDays = HistoryPeriodHelper.daysInMonth(containing: month, calendar: calendar)
        let worked = Set(
            sessions
                .filter { $0.clockOut != nil }
                .map { calendar.startOfDay(for: $0.date) }
        )
        let today = calendar.startOfDay(for: now)
        return allDays.filter { day in
            let start = calendar.startOfDay(for: day)
            return start <= today && !worked.contains(start)
        }
    }

    // MARK: - Aggregation

    /// Pay and hours for a set of sessions. A thin pass-through to `OvertimeCalculator`
    /// on purpose: the assistant must never do its own arithmetic on money.
    static func aggregatePay(
        sessions: [WorkSession],
        settings: WorkplaceSettings
    ) -> DayPayBreakdown {
        OvertimeCalculator.aggregate(
            sessions: sessions.filter { $0.clockOut != nil },
            settings: settings
        )
    }

    /// Distinct calendar days represented by `sessions`, in ascending order.
    static func distinctDays(
        in sessions: [WorkSession],
        calendar: Calendar = .current
    ) -> [Date] {
        Array(Set(sessions.map { calendar.startOfDay(for: $0.date) })).sorted()
    }

    // MARK: - Helpers

    static func minutesFromMidnight(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// `"HH:MM"` → minutes past midnight. Returns nil for anything that isn't a valid
    /// 24-hour time, so a malformed filter is dropped rather than silently treated as
    /// midnight (which would match every shift).
    static func parseTimeOfDay(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }
}
