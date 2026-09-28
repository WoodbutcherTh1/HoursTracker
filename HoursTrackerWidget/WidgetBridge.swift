import Foundation
import CoreFoundation
import ActivityKit

// MARK: - Money formatting (self-contained — the widget cannot import the app module)

enum WidgetPayFormatter {
    private static var formatters: [String: NumberFormatter] = [:]

    static func string(_ amount: Double, currencyCode: String) -> String {
        if let cached = formatters[currencyCode] {
            return cached.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatters[currencyCode] = formatter
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

// MARK: - Shared settings / session snapshots

/// Lightweight settings snapshot shared between the app and widget extension.
struct WidgetSettings: Codable, Equatable {
    var hourlyRate: Double
    var dailyGasAllowance: Double
    var standardDayHours: Double
    var ot125HoursCap: Double
    var breakMinutes: Int
    var currencyCode: String
    var weeklyStandardHours: Double
    var weeklyOvertimeCapHours: Double
    /// Planned break length for the break countdown. Optional so snapshots written
    /// by an older app build still decode.
    var breakTargetMinutes: Int? = nil
    /// The in-app language ("en" / "he" / "ar" / "ru") so the widget speaks the same
    /// language as the app, not just the device. Optional for older snapshots.
    var languageCode: String? = nil

    static let empty = WidgetSettings(
        hourlyRate: 0,
        dailyGasAllowance: 0,
        standardDayHours: 8.6,
        ot125HoursCap: 2.0,
        breakMinutes: 0,
        currencyCode: "ILS",
        weeklyStandardHours: 42,
        weeklyOvertimeCapHours: 12
    )
}

/// A minimal session snapshot the widget can read.
struct WidgetSession: Codable, Equatable {
    let id: UUID
    let clockIn: Date
    let clockOut: Date?
    let breakMinutes: Int
    let isNightShift: Bool
    /// Start of the break in progress (nil when not on break).
    var breakStart: Date? = nil
    /// Seconds of already-finished unpaid breaks in this (open) shift.
    var closedBreakSeconds: Double? = nil
    /// True when the running break is paid (workplace doesn't deduct breaks), so the
    /// paid clock keeps running through it.
    var breakIsPaid: Bool? = nil

    var isOpen: Bool { clockOut == nil }
    var isOnBreak: Bool { isOpen && breakStart != nil }

    /// Paid elapsed hours (total minus unpaid break). While the shift is open the
    /// recorded breaks — including one still running — are left out, so the figure
    /// stands still during a break.
    var effectiveHours: Double {
        let end = clockOut ?? Date()
        let raw = max(0, end.timeIntervalSince(clockIn) / 3600)
        guard isOpen else { return max(0, raw - Double(breakMinutes) / 60) }
        let running = breakIsPaid == true ? 0 : breakStart.map { max(0, end.timeIntervalSince($0)) } ?? 0
        return max(0, raw - ((closedBreakSeconds ?? 0) + running) / 3600)
    }
}

/// Widget button actions. Written to the shared suite + broadcast with a Darwin
/// notification so both the widget extension and the app can react.
enum WidgetAction: String {
    case clockIn = "clockIn"
    case clockOut = "clockOut"
    case startBreak = "startBreak"
    case endBreak = "endBreak"
}

// MARK: - Live Activity attributes

/// Attributes for the running-shift Live Activity.
/// Must be an identical type in the app and the widget extension (same file,
/// compiled into both targets via XcodeGen).
struct HoursActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedTime: TimeInterval
        var estimatedPay: Double
        var elapsedHours: Double
        /// Start of the break in progress; nil while working.
        var breakStart: Date? = nil
        /// Planned break length, for the Lock Screen / Dynamic Island countdown.
        var breakTargetMinutes: Int? = nil
        /// When the paid clock read 0 — set while it's running, so the Lock Screen can
        /// tick the hours with a system timer between app updates. Nil while the paid
        /// clock is stopped (unpaid break) or the shift is over.
        var paidClockStart: Date? = nil
        /// Whether `estimatedPay` is net (true) or gross — follows Home's picker.
        var payIsNet: Bool? = nil

        var isOnBreak: Bool { breakStart != nil }

        /// When the planned break ends (nil when not on break).
        var breakEnd: Date? {
            guard let breakStart else { return nil }
            return breakStart.addingTimeInterval(TimeInterval((breakTargetMinutes ?? 30) * 60))
        }
    }

    var clockInTime: Date
    var hourlyRate: Double
    var currencyCode: String
    var standardDayHours: Double
    var ot125HoursCap: Double
    var dailyGasAllowance: Double
    var breakMinutes: Int
}

// MARK: - Bridge

/// Bridge between the main app and the widget extension.
/// Data is stored in a shared App Group UserDefaults suite.
enum WidgetBridge {
    static let suiteName = "group.com.hourstracker.app"
    static let settingsKey = "widget_settings"
    static let sessionsKey = "widget_sessions"
    static let lastUpdateKey = "widget_last_update"
    static let hidePayKey = "widget_hide_pay"
    static let pendingActionKey = "widget_pending_action"
    static let pendingActionDateKey = "widget_pending_action_date"
    static let livePayKey = "widget_live_pay"
    static let livePayShowsNetKey = "widget_live_pay_net"

    /// Darwin notification name — works across the app ↔ widget processes.
    static let darwinActionNotification = "com.hourstracker.widget.action" as CFString

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Write

    static func update(settings: WidgetSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        suite?.set(data, forKey: settingsKey)
    }

    static func update(sessions: [WidgetSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        suite?.set(data, forKey: sessionsKey)
        suite?.set(Date(), forKey: lastUpdateKey)
    }

    /// The open shift's live pay curve (nil when clocked out) and which figure to show.
    static func update(livePay: LivePayCurve?, showsNet: Bool) {
        if let livePay, let data = try? JSONEncoder().encode(livePay) {
            suite?.set(data, forKey: livePayKey)
        } else {
            suite?.removeObject(forKey: livePayKey)
        }
        suite?.set(showsNet, forKey: livePayShowsNetKey)
    }

    static func readLivePay() -> LivePayCurve? {
        guard let data = suite?.data(forKey: livePayKey) else { return nil }
        return try? JSONDecoder().decode(LivePayCurve.self, from: data)
    }

    static var livePayShowsNet: Bool {
        suite?.bool(forKey: livePayShowsNetKey) ?? false
    }

    // NOTE: no `reloadTimelines` here — `WidgetCenter` requires linking WidgetKit
    // into every target that compiles this shared file (app, widget, tests). The
    // app-only bridge (`WidgetIntegration.swift`) owns `reloadWidgetTimelines()`.

    // MARK: - Privacy: hide pay amounts

    /// When true, widgets and the Live Activity mask money amounts («••••»).
    static var hidePay: Bool {
        get { suite?.bool(forKey: hidePayKey) ?? false }
        set { suite?.set(newValue, forKey: hidePayKey) }
    }

    /// Formats a pay amount, masking it entirely when privacy hiding is on.
    static func format(amount: Double, currencyCode: String) -> String {
        hidePay ? "••••" : WidgetPayFormatter.string(amount, currencyCode: currencyCode)
    }

    // MARK: - Pending action (widget button → app)

    /// Record a button tap so the app can apply it (the app owns persistence,
    /// Live Activity, and sync — the widget only signals).
    static func recordPendingAction(_ action: WidgetAction) {
        suite?.set(action.rawValue, forKey: pendingActionKey)
        suite?.set(Date(), forKey: pendingActionDateKey)
        postDarwinNotification()
    }

    /// Read + clear the pending action (nil when nothing is pending), together with
    /// when it was tapped. The app may only get to apply it much later (it wasn't
    /// running), so the tap time — not the time it was applied — is when the
    /// break / shift really started.
    static func consumePendingActionWithDate() -> (action: WidgetAction, tappedAt: Date?)? {
        guard let raw = suite?.string(forKey: pendingActionKey),
              let action = WidgetAction(rawValue: raw) else { return nil }
        let tappedAt = suite?.object(forKey: pendingActionDateKey) as? Date
        suite?.removeObject(forKey: pendingActionKey)
        suite?.removeObject(forKey: pendingActionDateKey)
        return (action, tappedAt)
    }

    /// Cross-process wake-up: the app observes this name while running.
    static func postDarwinNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinActionNotification),
            nil, nil, false
        )
    }

    // MARK: - Read (widget extension)

    static func readSettings() -> WidgetSettings {
        guard let data = suite?.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(WidgetSettings.self, from: data) else {
            return .empty
        }
        return settings
    }

    static func readSessions() -> [WidgetSession] {
        guard let data = suite?.data(forKey: sessionsKey),
              let sessions = try? JSONDecoder().decode([WidgetSession].self, from: data) else {
            return []
        }
        return sessions
    }

    /// Today's completed sessions (clockOut != nil).
    static func todayCompletedSessions(
        from sessions: [WidgetSession],
        calendar: Calendar = .current
    ) -> [WidgetSession] {
        let today = calendar.startOfDay(for: Date())
        return sessions.filter { s in
            !s.isOpen && calendar.isDate(s.clockIn, inSameDayAs: today)
        }
    }

    /// All sessions (open or completed) whose clock-in falls in the current week.
    static func weekSessions(
        from sessions: [WidgetSession],
        calendar: Calendar = .current
    ) -> [WidgetSession] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return sessions.filter { $0.clockIn >= interval.start && $0.clockIn < interval.end }
    }

    /// All sessions (open or completed) whose clock-in falls in the current month.
    static func monthSessions(
        from sessions: [WidgetSession],
        calendar: Calendar = .current
    ) -> [WidgetSession] {
        guard let interval = calendar.dateInterval(of: .month, for: Date()) else { return [] }
        return sessions.filter { $0.clockIn >= interval.start && $0.clockIn < interval.end }
    }

    /// The currently open session, if any.
    static func openSession(from sessions: [WidgetSession]) -> WidgetSession? {
        sessions.first { $0.isOpen }
    }

    // MARK: - Pay Estimation

    /// Lightweight pay estimate — just the daily OT split, no weekly cap or tax.
    static func estimatePay(
        elapsedHours: Double,
        settings: WidgetSettings
    ) -> Double {
        let rate = settings.hourlyRate
        guard rate > 0 else { return 0 }
        let standard = settings.standardDayHours
        let regular = min(elapsedHours, standard)
        let ot125 = min(max(0, elapsedHours - standard), settings.ot125HoursCap)
        let ot150 = max(0, elapsedHours - standard - settings.ot125HoursCap)
        let gas = settings.dailyGasAllowance
        return (regular * rate) + (ot125 * rate * 1.25) + (ot150 * rate * 1.5) + gas
    }
}