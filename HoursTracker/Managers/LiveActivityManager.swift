import ActivityKit
import Foundation

/// Manages the lifecycle of the running-shift Live Activity.
/// Only the main app target should call these methods — the widget extension
/// is read-only.
enum LiveActivityManager {
    private static var activity: Activity<HoursActivityAttributes>?

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
        guard let activity else { return }
        let state = makeState(session: session, settings: settings)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - End

    /// End the Live Activity when the user clocks out.
    @available(iOS 16.1, *)
    static func end(session: WorkSession, settings: WorkplaceSettings) {
        guard let activity else { return }
        let state = makeState(session: session, settings: settings)
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.seconds(30)))
        }
        self.activity = nil
    }

    // MARK: - Helpers

    @available(iOS 16.1, *)
    private static func makeState(
        session: WorkSession,
        settings: WorkplaceSettings
    ) -> HoursActivityAttributes.ContentState {
        let elapsed = session.effectiveHours
        let pay = WidgetBridge.estimatePay(
            elapsedHours: elapsed,
            settings: WidgetBridge.snapshot(from: settings)
        )
        return HoursActivityAttributes.ContentState(
            elapsedTime: session.elapsedSeconds,
            estimatedPay: pay,
            elapsedHours: elapsed
        )
    }
}
