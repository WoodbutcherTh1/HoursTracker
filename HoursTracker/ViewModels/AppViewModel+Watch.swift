import Foundation

extension AppViewModel {
    /// Precomputed state for the paired Watch app — see `WatchConnectivityManager`.
    /// Uses the same `OvertimeCalculator.aggregate` the Export tab's totals use, so
    /// the Watch shows real net/gross pay (weekly OT cap, tax estimate) rather than
    /// a simplified re-derivation.
    var watchSnapshot: WatchSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let todaySessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: today) }
        let todayBreakdown = OvertimeCalculator.aggregate(sessions: todaySessions, settings: settings)
        // `aggregate` only counts completed sessions — add the still-running shift's
        // elapsed hours so "today" doesn't freeze the moment a shift starts.
        var todayHours = todayBreakdown.totalHours
        if let active = activeSession, calendar.isDate(active.date, inSameDayAs: today) {
            todayHours += active.effectiveHours
        }

        let weekSessions: [WorkSession]
        if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
            weekSessions = sessions.filter { $0.clockIn >= interval.start && $0.clockIn < interval.end }
        } else {
            weekSessions = []
        }
        let weekBreakdown = OvertimeCalculator.aggregate(sessions: weekSessions, settings: settings)

        return WatchSnapshot(
            isClockedIn: isClockedIn,
            clockInTime: activeSession?.clockIn,
            todayHours: max(0, todayHours),
            todayNetPay: todayBreakdown.netPay,
            todayGrossPay: todayBreakdown.grossPay,
            weekHours: weekBreakdown.totalHours,
            weekNetPay: weekBreakdown.netPay,
            weekGrossPay: weekBreakdown.grossPay,
            currencyCode: settings.currencyCode,
            workplaceName: settings.workplaceName,
            generatedAt: now
        )
    }
}
