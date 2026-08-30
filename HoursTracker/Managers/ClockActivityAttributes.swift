import ActivityKit
import Foundation

/// Shared between the app (starts/updates/ends the activity) and the widget extension
/// (renders it) — compiled into both targets, see project.yml. `clockInDate` is fixed
/// for the life of one activity (one continuous clock-in-to-clock-out span), so it lives
/// on `ClockActivityAttributes` itself rather than `ContentState`; the native
/// `Text(date, style: .timer)` widget view ticks on its own from it, no updates needed.
/// `ContentState` carries the one thing that actually changes: today's running pay.
struct ClockActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var todayGrossPay: Double
        var currencyCode: String
    }

    var clockInDate: Date
}
