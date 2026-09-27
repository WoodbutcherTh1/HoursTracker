import Foundation

/// Targets for the Home stat cards' progress bars.
///
/// DISPLAY ONLY — never used in pay math. Reads the onboarding answers in
/// `DisplayPreferences` (expected weekly hours and week pattern), never
/// `weeklyStandardHours` or the rest days. A `nil` target means "no bar": the card
/// shows its number alone instead of an empty 0% bar.
struct HomeStatGoals: Equatable {
    let weeklyGoalHours: Int?
    let weekPattern: WeekPattern?
    let customWorkdays: Set<Int>

    static func current(_ display: DisplayPreferences = .shared) -> HomeStatGoals {
        HomeStatGoals(
            weeklyGoalHours: display.weeklyGoalHoursDisplayOnly,
            weekPattern: display.weekPattern,
            customWorkdays: display.customWorkdays
        )
    }

    /// Workdays of a fixed pattern; `nil` when the week varies or was never set.
    private var fixedWorkdays: Set<Int>? {
        guard let weekPattern, weekPattern != .varies else { return nil }
        let days = weekPattern.workdays(custom: customWorkdays)
        return days.isEmpty ? nil : days
    }

    /// Weekly goal ÷ workdays, only on a workday of a fixed pattern — a day off
    /// has no target, so it doesn't show an empty bar.
    func todayHoursTarget(on date: Date, calendar: Calendar) -> Double? {
        guard let goal = weeklyGoalHours, goal > 0, let days = fixedWorkdays,
              days.contains(calendar.component(.weekday, from: date)) else { return nil }
        return Double(goal) / Double(days.count)
    }

    /// The weekly goal itself — valid for any pattern, "varies" included.
    var weekHoursTarget: Double? {
        guard let goal = weeklyGoalHours, goal > 0 else { return nil }
        return Double(goal)
    }

    /// Shifts expected this month: the month's days that fall on a workday.
    func monthShiftTarget(for date: Date, calendar: Calendar) -> Int? {
        guard let days = fixedWorkdays,
              let dayCount = calendar.range(of: .day, in: .month, for: date)?.count,
              let start = calendar.dateInterval(of: .month, for: date)?.start else { return nil }
        let workdays = (0..<dayCount).filter { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return false }
            return days.contains(calendar.component(.weekday, from: day))
        }.count
        return workdays > 0 ? workdays : nil
    }

    /// 0…1 fill for a value against a target; `nil` without a target.
    static func progress(_ value: Double, target: Double?) -> Double? {
        guard let target, target > 0 else { return nil }
        return min(max(value / target, 0), 1)
    }
}
