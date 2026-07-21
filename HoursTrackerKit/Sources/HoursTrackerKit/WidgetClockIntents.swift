import AppIntents
import Foundation

/// Shared App Intent: clock in using the same event shape the phone applies via `applyWatchClockEvent`.
/// Parameter-free — Siri / Shortcuts run immediately with no follow-up questions.
public struct ClockInIntent: AppIntent {
    public static var title: LocalizedStringResource = "Clock In"
    public static var description = IntentDescription("Start an open HoursTracker shift.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = WidgetClockService.clockIn()
        return .result(dialog: IntentDialog(stringLiteral: ClockIntentDialogCopy.dialogMessage(for: outcome)))
    }
}

/// Shared App Intent: clock out the open shift.
public struct ClockOutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Clock Out"
    public static var description = IntentDescription("End the open HoursTracker shift.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = WidgetClockService.clockOut()
        return .result(dialog: IntentDialog(stringLiteral: ClockIntentDialogCopy.dialogMessage(for: outcome)))
    }
}

/// Toggle clock state — primary control for Small widgets and watch complications.
/// Shortcuts title spells out In/Out so the action is never a vague “Clock”.
public struct ToggleClockIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Clock In/Out"
    public static var description = IntentDescription("Clock in if out, or clock out if in.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = WidgetClockService.toggle()
        return .result(dialog: IntentDialog(stringLiteral: ClockIntentDialogCopy.dialogMessage(for: outcome)))
    }
}
