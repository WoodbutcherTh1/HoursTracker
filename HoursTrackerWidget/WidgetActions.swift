import AppIntents
import WidgetKit

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

extension WidgetBridge {
    /// Deep links for tapping (non-button) areas of the widget.
    static let deepLinkHome = "hourstracker://tab/home"
    static let deepLinkHistory = "hourstracker://tab/history"
}

// MARK: - Widget Week Navigation (Home Screen, large size)

/// Kind string shared with `HoursMediumWidget` — reloading just this kind
/// avoids nuking the small widget's timeline on every week-nav tap.
private let weekNavWidgetKind = "HoursMediumWidget"

struct PreviousWeekIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Week"
    static var description = IntentDescription("Show last week's hours")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetBridge.selectedWeekOffset -= 1
        WidgetCenter.shared.reloadTimelines(ofKind: weekNavWidgetKind)
        return .result()
    }
}

struct NextWeekIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Week"
    static var description = IntentDescription("Show next week's hours")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        // Never navigate past the current week — there's nothing to show yet.
        WidgetBridge.selectedWeekOffset = min(0, WidgetBridge.selectedWeekOffset + 1)
        WidgetCenter.shared.reloadTimelines(ofKind: weekNavWidgetKind)
        return .result()
    }
}
