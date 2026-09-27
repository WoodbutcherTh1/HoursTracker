import AppIntents
import Foundation

// MARK: - Shift intents (widget buttons → app, without opening the app)
//
// Compiled into BOTH the app and the widget extension (see project.yml). The widget
// needs the types for its `Button(intent:)` call sites; the app needs them to run
// them. Because they conform to `LiveActivityIntent`, iOS performs them in the
// app's process — launching it in the background when it isn't running — so a tap
// on the widget clocks in/out or starts/ends a break right away, through the same
// code path as the in-app buttons (persistence, sync, Live Activity, Watch), and the
// widget refreshes with the result. Nothing opens on screen.

/// Bridge from an intent to the app's real clock/break logic. The app installs
/// `applyPending` at launch (AppDelegate); inside the widget extension it stays nil
/// and the tap is only recorded, to be applied the next time the app runs.
enum ShiftIntentRouter {
    @MainActor static var applyPending: (@MainActor () -> Void)?

    /// Records the tap (with its time) in the shared App Group suite, then applies
    /// it immediately when running inside the app. Recording first means a tap the
    /// app can't apply yet — e.g. its data is still locked by Data Protection while
    /// the phone is locked — isn't lost: it's applied, with the original tap time,
    /// once the data is readable.
    @MainActor
    static func run(_ action: WidgetAction) {
        WidgetBridge.recordPendingAction(action)
        applyPending?()
    }
}

struct ClockInIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Clock In"
    static var description = IntentDescription("Start your work shift")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ShiftIntentRouter.run(.clockIn)
        return .result()
    }
}

struct ClockOutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Clock Out"
    static var description = IntentDescription("End your work shift")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ShiftIntentRouter.run(.clockOut)
        return .result()
    }
}

struct StartBreakIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Break"
    static var description = IntentDescription("Pause your shift for a break")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ShiftIntentRouter.run(.startBreak)
        return .result()
    }
}

struct EndBreakIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Break"
    static var description = IntentDescription("Back to work after a break")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ShiftIntentRouter.run(.endBreak)
        return .result()
    }
}
