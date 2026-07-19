import AppIntents
import Foundation

/// Shared App Intent: clock in using the same event shape the phone applies via `applyWatchClockEvent`.
public struct ClockInIntent: AppIntent {
    public static var title: LocalizedStringResource = "Clock In"
    public static var description = IntentDescription("Start an open HoursTracker shift.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = WidgetClockService.clockIn()
        switch outcome {
        case .clockedIn:
            return .result(dialog: "Clocked in")
        case .rejectedAlreadyIn:
            return .result(dialog: "Already clocked in")
        case .rejectedNoSnapshot:
            return .result(dialog: "Open HoursTracker once to sync")
        default:
            return .result(dialog: "Could not clock in")
        }
    }
}

/// Shared App Intent: clock out the open shift.
public struct ClockOutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Clock Out"
    public static var description = IntentDescription("End the open HoursTracker shift.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = WidgetClockService.clockOut()
        switch outcome {
        case .clockedOut:
            return .result(dialog: "Clocked out")
        case .rejectedNoOpenSession:
            return .result(dialog: "Not clocked in")
        case .rejectedNoSnapshot:
            return .result(dialog: "Open HoursTracker once to sync")
        default:
            return .result(dialog: "Could not clock out")
        }
    }
}

/// Toggle clock state — primary control for Small widgets and watch complications.
public struct ToggleClockIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Clock"
    public static var description = IntentDescription("Clock in if out, or clock out if in.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = WidgetClockService.toggle()
        switch outcome {
        case .clockedIn:
            return .result(dialog: "Clocked in")
        case .clockedOut:
            return .result(dialog: "Clocked out")
        case .rejectedNoSnapshot:
            return .result(dialog: "Open HoursTracker once to sync")
        case .rejectedAlreadyIn:
            return .result(dialog: "Already clocked in")
        case .rejectedNoOpenSession:
            return .result(dialog: "Not clocked in")
        }
    }
}
