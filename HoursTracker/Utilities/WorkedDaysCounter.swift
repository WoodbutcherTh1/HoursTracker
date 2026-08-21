import Foundation

/// How many *days* someone worked in a calendar month, and whether a shift that is
/// running right now is about to add one more.
///
/// Deliberately not the same thing as Home's `monthShiftCount`, which counts completed
/// sessions: clock in and out twice on one day and that returns 2. People read "days
/// worked" as days on the calendar, so this de-duplicates by `startOfDay` first and
/// counts distinct days instead.
///
/// The month reference is `calendar.isDate(_:equalTo:toGranularity:.month)` — the plain
/// calendar month, matching `monthShiftCount`, not the configurable payroll period that
/// History's period chrome navigates.
enum WorkedDaysCounter {
    /// Distinct calendar days in `month`'s calendar month with at least one completed
    /// session. Open (running) shifts do not count until they are clocked out.
    static func distinctWorkedDays(
        in sessions: [WorkSession],
        month: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        var days: Set<Date> = []
        for session in sessions where session.clockOut != nil {
            guard calendar.isDate(session.date, equalTo: month, toGranularity: .month) else {
                continue
            }
            days.insert(calendar.startOfDay(for: session.date))
        }
        return days.count
    }

    /// Whether `day` already has a completed session — i.e. whether it is already part
    /// of `distinctWorkedDays`.
    static func isDayAlreadyCounted(
        _ day: Date,
        in sessions: [WorkSession],
        calendar: Calendar = .current
    ) -> Bool {
        sessions.contains { session in
            session.clockOut != nil && calendar.isDate(session.date, inSameDayAs: day)
        }
    }

    /// True when a running shift will push the day count up by one the moment it is
    /// clocked out — the condition behind History's green "+1?" bubble.
    ///
    /// False when there is no open shift, when the open shift's day already has an
    /// earlier completed session (that day is counted whatever happens next), or when
    /// the open shift started outside the month being displayed.
    static func openShiftWouldAddADay(
        activeSession: WorkSession?,
        sessions: [WorkSession],
        month: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let activeSession, activeSession.clockOut == nil else { return false }
        guard calendar.isDate(activeSession.date, equalTo: month, toGranularity: .month) else {
            return false
        }
        return !isDayAlreadyCounted(activeSession.date, in: sessions, calendar: calendar)
    }
}
