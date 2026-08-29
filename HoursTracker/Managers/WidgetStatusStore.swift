import Foundation
import WidgetKit

/// Phone-side writer for both widgets' shared snapshot (Lock Screen status +
/// Home Screen stats). Both widgets only ever read this suite — neither mutates
/// session data itself; tapping either opens the app via `hourstracker://clockToggle`,
/// which performs the actual clock in/out through the normal `AppViewModel` path (see
/// the note on the `HoursTrackerWidget` target in project.yml for why). Inert by
/// default: without the App Group entitlement actually applied
/// (docs/HoursTracker.entitlements.appgroup.example), `UserDefaults(suiteName:)` still
/// returns an instance but writes never reach the widget process, so this silently
/// no-ops rather than failing.
///
/// NOT verified against a real build — written without Xcode or a widget-enabled
/// simulator available in this environment.
enum WidgetStatusStore {
    static let appGroupID = "group.com.hourstracker.app"
    static let clockStatusWidgetKind = "HoursTrackerClockStatusWidget"
    static let homeStatsWidgetKind = "HoursTrackerHomeStatsWidget"

    /// Recomputes the exact same today/week/month figures `HomeView` shows
    /// (`todayHours`/`weekHours`/`monthShiftCount`/`todayPayBreakdown`) and pushes them
    /// to the shared suite, then reloads both widgets. Call after any change that could
    /// move those numbers — not just clock in/out, since edits, deletes, and imports in
    /// History also change them.
    static func refresh(sessions: [WorkSession], settings: WorkplaceSettings) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let calendar = Calendar.current
        let now = Date()
        let completed = sessions.filter { $0.clockOut != nil }

        let today = calendar.startOfDay(for: now)
        let todaySessions = completed.filter { calendar.isDate($0.date, inSameDayAs: today) }
        let todayHours = todaySessions.reduce(0) { $0 + $1.totalHours }
        let todayPay = OvertimeCalculator.aggregate(sessions: todaySessions, settings: settings)

        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: now, end: now)
        let weekHours = completed
            .filter { weekInterval.contains($0.date) }
            .reduce(0) { $0 + $1.totalHours }

        let monthWorkedDays = completed.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }.count

        let activeSession = sessions.filter(\.isOpen).max { $0.clockIn < $1.clockIn }

        defaults.set(activeSession != nil, forKey: "isClockedIn")
        if let clockIn = activeSession?.clockIn {
            defaults.set(clockIn.timeIntervalSince1970, forKey: "clockInDate")
        } else {
            defaults.removeObject(forKey: "clockInDate")
        }
        defaults.set(todayHours, forKey: "todayHours")
        defaults.set(weekHours, forKey: "weekHours")
        defaults.set(monthWorkedDays, forKey: "monthWorkedDays")
        defaults.set(todayPay.grossPay, forKey: "todayGrossPay")
        defaults.set(todayPay.currencyCode, forKey: "currencyCode")

        WidgetCenter.shared.reloadTimelines(ofKind: clockStatusWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: homeStatsWidgetKind)
    }
}
