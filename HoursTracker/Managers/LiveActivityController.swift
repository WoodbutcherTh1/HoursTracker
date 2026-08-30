import Foundation
import ActivityKit

/// Starts/updates/ends the Lock Screen + Dynamic Island Live Activity for the current
/// clock-in session. This is a genuine ActivityKit activity — distinct from
/// `WidgetStatusStore`'s snapshot widget — and is what shows a persistently-updating
/// card without a tap, including in the Dynamic Island on Pro models.
///
/// Local-only: no push token requested, since there is no server to send updates from.
/// The live elapsed timer needs no updates at all (native `Text(date, style: .timer)`
/// ticks from `clockInDate` on its own); `update(sessions:settings:)` only refreshes
/// today's running pay, called from the same debounced sink `WidgetStatusStore` uses.
///
/// NOT verified against a real build — ActivityKit needs a real device or a
/// Live-Activity-enabled simulator, neither available in this environment.
@MainActor
final class LiveActivityController {
    private var activity: Activity<ClockActivityAttributes>?

    /// No-op if an activity for this exact clock-in is already running — safe to call
    /// both from `clockIn()` and from launch-time reconciliation.
    func start(clockInDate: Date, settings: WorkplaceSettings) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity, activity.attributes.clockInDate == clockInDate { return }

        // A stale activity from a session that ended without going through end() (e.g.
        // the app was killed) — clear it before starting the real one.
        for existing in Activity<ClockActivityAttributes>.activities {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
        }

        let attributes = ClockActivityAttributes(clockInDate: clockInDate)
        let state = ClockActivityAttributes.ContentState(todayGrossPay: 0, currencyCode: settings.currencyCode)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    func update(sessions: [WorkSession], settings: WorkplaceSettings) {
        guard let activity else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todaySessions = sessions.filter {
            $0.clockOut != nil && calendar.isDate($0.date, inSameDayAs: today)
        }
        let totals = OvertimeCalculator.aggregate(sessions: todaySessions, settings: settings)
        let state = ClockActivityAttributes.ContentState(
            todayGrossPay: totals.grossPay,
            currencyCode: totals.currencyCode
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
