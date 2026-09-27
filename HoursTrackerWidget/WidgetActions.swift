import AppIntents

// MARK: - Widget Interactive Buttons (iOS 17+)

/// Clocking in/out from the widget is a two-step handoff:
/// 1. The intent (this file) records the action in the shared App Group suite.
/// 2. The app (which owns persistence, sync, and the Live Activity) consumes
///    the pending action — via a Darwin notification wake while running, or on
///    next launch — and applies it.
/// This keeps the widget stateless: it never writes sessions itself.

struct ClockInIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock In"
    static var description = IntentDescription("Start your work shift")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetBridge.recordPendingAction(.clockIn)
        return .result()
    }
}

struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock Out"
    static var description = IntentDescription("End your work shift")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetBridge.recordPendingAction(.clockOut)
        return .result()
    }
}

struct StartBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Break"
    static var description = IntentDescription("Pause your shift for a break")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetBridge.recordPendingAction(.startBreak)
        return .result()
    }
}

struct EndBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "End Break"
    static var description = IntentDescription("Back to work after a break")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetBridge.recordPendingAction(.endBreak)
        return .result()
    }
}

extension WidgetBridge {
    /// Deep links for tapping (non-button) areas of the widget.
    static let deepLinkHome = "hourstracker://tab/home"
    static let deepLinkHistory = "hourstracker://tab/history"
}