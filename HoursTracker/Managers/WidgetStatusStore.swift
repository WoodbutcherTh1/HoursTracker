import Foundation
import WidgetKit

/// Phone-side writer for the Lock Screen status widget's shared snapshot. The widget
/// only ever reads this suite — it never mutates session data itself (see the note on
/// the `HoursTrackerWidget` target in project.yml for why). Inert by default: without
/// the App Group entitlement actually applied (docs/HoursTracker.entitlements.appgroup.example),
/// `UserDefaults(suiteName:)` still returns an instance but writes never reach the
/// widget process, so this silently no-ops rather than failing.
///
/// NOT verified against a real build — written without Xcode or a widget-enabled
/// simulator available in this environment.
enum WidgetStatusStore {
    static let appGroupID = "group.com.hourstracker.app"
    static let widgetKind = "HoursTrackerClockStatusWidget"

    static func push(isClockedIn: Bool, since: Date?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(isClockedIn, forKey: "isClockedIn")
        if let since {
            defaults.set(since.timeIntervalSince1970, forKey: "clockInDate")
        } else {
            defaults.removeObject(forKey: "clockInDate")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
