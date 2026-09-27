import ActivityKit
import Foundation

/// Manages the lifecycle of the running-shift Live Activity.
/// Only the main app target should call these methods — the widget extension
/// is read-only.
enum LiveActivityManager {
    private static var activity: Activity<HoursActivityAttributes>?

    /// The running activity, even if this process didn't start it. A widget-button
    /// intent can run in a fresh background launch of the app, where the `activity`
    /// reference from the launch that clocked in is gone — without this fallback a
    /// clock-out from the widget would leave the Lock Screen banner running.
    @available(iOS 16.1, *)
    private static var current: Activity<HoursActivityAttributes>? {
        if let activity { return activity }
        activity = Activity<HoursActivityAttributes>.activities.first { $0.activityState == .active }
        return activity
    }

    // MARK: - Start

    /// Start a new Live Activity when the user clocks in.
    @available(iOS 16.1, *)
    static func start(session: WorkSession, settings: WorkplaceSettings) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = HoursActivityAttributes.from(session: session, settings: settings)
        let state = makeState(session: session, settings: settings)

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("[LiveActivity] Failed to start: \(error)")
            #endif
        }
    }

    // MARK: - Update

    /// Push an updated content state (typically every ~60 s from the app's timer).
    @available(iOS 16.1, *)
    static func update(session: WorkSession, settings: WorkplaceSettings) {
        guard let activity = current else { return }
        let state = makeState(session: session, settings: settings)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - End

    /// End the Live Activity when the user clocks out.
    @available(iOS 16.1, *)
    static func end(session: WorkSession, settings: WorkplaceSettings) {
        guard let activity = current else { return }
        let state = makeState(session: session, settings: settings)
        Task {
            // `ActivityDismissalPolicy.after` takes a Date (the dismissal time),
            // not a Duration — keep the live banner on screen for 30s.
            await activity.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30))
            )
        }
        self.activity = nil
    }

    // MARK: - Helpers

    @available(iOS 16.1, *)
    private static func makeState(
        session: WorkSession,
        settings: WorkplaceSettings
    ) -> HoursActivityAttributes.ContentState {
        // `effectiveHours` is 0 for an open session (it needs a clock-out), which left
        // the banner reading 0.0h / 0 pay all shift. Use paid time so far instead —
        // wall clock minus recorded breaks, so it also stands still during a break.
        let paidSeconds = session.paidElapsedSeconds(breaksArePaid: settings.breaksArePaid)
        let elapsed = paidSeconds / 3600
        let pay = WidgetBridge.estimatePay(
            elapsedHours: elapsed,
            settings: WidgetBridge.snapshot(from: settings)
        )
        return HoursActivityAttributes.ContentState(
            elapsedTime: paidSeconds,
            estimatedPay: pay,
            elapsedHours: elapsed,
            breakStart: session.activeBreak?.start,
            breakTargetMinutes: NotificationPreferences.shared.breakTargetMinutes
        )
    }
}
