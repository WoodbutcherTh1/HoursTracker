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
    static func start(
        session: WorkSession,
        settings: WorkplaceSettings,
        curve: LivePayCurve? = nil,
        showsNet: Bool = false
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // One banner at a time: anything left from an earlier shift goes first.
        endAll()
        let attributes = HoursActivityAttributes.from(session: session, settings: settings)
        let state = makeState(session: session, settings: settings, curve: curve, showsNet: showsNet)

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
    static func update(
        session: WorkSession,
        settings: WorkplaceSettings,
        curve: LivePayCurve? = nil,
        showsNet: Bool = false
    ) {
        guard let activity = current else { return }
        // The clock-in time is part of the activity's fixed attributes, so after the
        // shift's start is edited (e.g. 7:03 → 7:30) the banner would keep the old
        // time and pay. Replace it with one built from the edited shift.
        if abs(activity.attributes.clockInTime.timeIntervalSince(session.clockIn)) > 1 {
            start(session: session, settings: settings, curve: curve, showsNet: showsNet)
            return
        }
        let state = makeState(session: session, settings: settings, curve: curve, showsNet: showsNet)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - End

    /// End the Live Activity when the user clocks out.
    @available(iOS 16.1, *)
    static func end(
        session: WorkSession,
        settings: WorkplaceSettings,
        curve: LivePayCurve? = nil,
        showsNet: Bool = false
    ) {
        let activities = Activity<HoursActivityAttributes>.activities
        self.activity = nil
        guard !activities.isEmpty else { return }
        var state = makeState(session: session, settings: settings, curve: curve, showsNet: showsNet)
        state.paidClockStart = nil
        state.breakStart = nil
        // Gone from the Lock Screen right away. It used to linger 30 s with its Clock
        // Out and Break buttons, which read as "clock-out didn't work". Every
        // activity is ended, not just the one this process knows about.
        Task {
            for activity in activities {
                await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
    }

    /// Ends every HoursTracker Live Activity at once — before a new one starts, and
    /// when the app sees no open shift but a banner is still up (a shift closed from
    /// the editor, deleted, or closed on another device).
    @available(iOS 16.1, *)
    static func endAll() {
        let activities = Activity<HoursActivityAttributes>.activities
        self.activity = nil
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Helpers

    @available(iOS 16.1, *)
    private static func makeState(
        session: WorkSession,
        settings: WorkplaceSettings,
        curve: LivePayCurve?,
        showsNet: Bool
    ) -> HoursActivityAttributes.ContentState {
        let now = Date()
        let isPaused = session.isOnBreak && !settings.breaksArePaid
        let paidSeconds: Double
        let pay: Double
        if let curve, curve.sessionID == session.id {
            // Same curve Home, the Watch and the widgets read — same figure everywhere.
            paidSeconds = curve.paidSeconds(at: now)
            pay = curve.pay(at: now, net: showsNet)
        } else {
            // Fallback (e.g. the final state at clock-out): paid time so far — wall
            // clock minus unpaid breaks — priced with the widget's quick estimate.
            paidSeconds = session.paidElapsedSeconds(now: now, breaksArePaid: settings.breaksArePaid)
            pay = WidgetBridge.estimatePay(
                elapsedHours: paidSeconds / 3600,
                settings: WidgetBridge.snapshot(from: settings)
            )
        }
        return HoursActivityAttributes.ContentState(
            elapsedTime: paidSeconds,
            estimatedPay: pay,
            elapsedHours: paidSeconds / 3600,
            breakStart: session.activeBreak?.start,
            breakTargetMinutes: NotificationPreferences.shared.breakTargetMinutes,
            // A running paid clock lets the Lock Screen tick the hours by itself.
            paidClockStart: isPaused ? nil : now.addingTimeInterval(-paidSeconds),
            payIsNet: curve != nil && showsNet
        )
    }
}
