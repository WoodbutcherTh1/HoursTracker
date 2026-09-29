import Foundation

/// What Siri says, built from the user's own shifts and settings — pure, so it can
/// be tested without Siri. Totals use the same engine as Home and History
/// (`OvertimeCalculator.aggregate`); shifts count on the day they started.
struct SiriReport {
    enum Period: CaseIterable {
        case today, thisWeek, thisMonth, lastMonth
    }

    struct Totals: Equatable {
        let shifts: Int
        let hours: Double
        let breakdown: DayPayBreakdown?
    }

    let sessions: [WorkSession]
    let settings: WorkplaceSettings
    var now = Date()
    var calendar = Calendar.current

    func interval(for period: Period) -> DateInterval? {
        switch period {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .lastMonth:
            guard let previous = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: previous)
        }
    }

    func totals(for period: Period) -> Totals {
        guard let interval = interval(for: period) else { return Totals(shifts: 0, hours: 0, breakdown: nil) }
        let finished = sessions.filter { $0.clockOut != nil && interval.contains($0.date) }
        guard !finished.isEmpty else { return Totals(shifts: 0, hours: 0, breakdown: nil) }
        return Totals(
            shifts: finished.count,
            hours: finished.reduce(0) { $0 + $1.effectiveHours },
            breakdown: OvertimeCalculator.aggregate(sessions: finished, settings: settings, calendar: calendar)
        )
    }

    /// 6.72 → "6:43".
    static func clock(hours: Double) -> String {
        ShiftSummaryNotifier.hoursText(hours)
    }

    static func periodName(_ period: Period) -> String {
        switch period {
        case .today: return L10n.siriPeriodToday
        case .thisWeek: return L10n.siriPeriodThisWeek
        case .thisMonth: return L10n.siriPeriodThisMonth
        case .lastMonth: return L10n.siriPeriodLastMonth
        }
    }

    /// "≈ ₪337.63 gross", or nil when pay is hidden on widgets / Lock Screen.
    static func payText(_ breakdown: DayPayBreakdown, showsNet: Bool, hidden: Bool) -> String? {
        guard !hidden else { return nil }
        return L10n.notifShiftSummaryPay(
            showsNet ? breakdown.formattedNetPay : breakdown.formattedGrossPay,
            showsNet ? L10n.historyPayNet : L10n.historyPayGross
        )
    }

    /// "This month: 142:30 hours · ≈ ₪6,120.00 gross" / "This week: no shifts yet."
    func totalsSentence(for period: Period, showsNet: Bool, payHidden: Bool) -> String {
        let name = Self.periodName(period)
        let result = totals(for: period)
        guard let breakdown = result.breakdown else { return L10n.siriTotalsEmpty(name) }
        let hours = Self.clock(hours: result.hours)
        if let pay = Self.payText(breakdown, showsNet: showsNet, hidden: payHidden) {
            return L10n.siriTotals(name, hours, pay)
        }
        return L10n.siriTotalsNoPay(name, hours)
    }
}
