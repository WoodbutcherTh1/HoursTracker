import Foundation
import CoreFoundation
import ActivityKit
import os

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

    var isOpen: Bool { clockOut == nil }

    /// Paid elapsed hours (total minus unpaid break), as of right now.
    var effectiveHours: Double { effectiveHours(asOf: Date()) }

    /// Paid elapsed hours as of an arbitrary reference date, for an open
    /// session. Lets the widget's timeline provider pre-compute a short run
    /// of future snapshots (see `HoursTimelineProvider`) so elapsed time and
    /// earnings visibly progress instead of freezing at whatever moment the
    /// timeline last happened to rebuild.
    func effectiveHours(asOf referenceDate: Date) -> Double {
        let end = clockOut ?? referenceDate
        let raw = max(0, end.timeIntervalSince(clockIn) / 3600)
        return max(0, raw - Double(breakMinutes) / 60)
    }
}

/// Widget button actions. Written to the shared suite + broadcast with a Darwin
/// notification so both the widget extension and the app can react.
enum WidgetAction: String {
    case clockIn = "clockIn"
    case clockOut = "clockOut"
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
    static let selectedWeekOffsetKey = "widget_selected_week_offset"

    /// Darwin notification name — works across the app ↔ widget processes.
    static let darwinActionNotification = "com.hourstracker.widget.action" as CFString

    private static let logger = Logger(subsystem: "com.hourstracker.app", category: "widgetBridge")

    private static var suite: UserDefaults? {
        let defaults = UserDefaults(suiteName: suiteName)
        if defaults == nil {
            logger.error("App Group suite '\(suiteName, privacy: .public)' is unreachable from this process")
        }
        return defaults
    }

    // MARK: - Write

    static func update(settings: WidgetSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            logger.error("Failed to encode WidgetSettings for the shared suite")
            return
        }
        suite?.set(data, forKey: settingsKey)
        logger.notice("Wrote settings to shared suite (\(data.count, privacy: .public) bytes)")
    }

    static func update(sessions: [WidgetSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else {
            logger.error("Failed to encode \(sessions.count, privacy: .public) WidgetSessions for the shared suite")
            return
        }
        suite?.set(data, forKey: sessionsKey)
        suite?.set(Date(), forKey: lastUpdateKey)
        logger.notice("Wrote \(sessions.count, privacy: .public) sessions to shared suite (\(data.count, privacy: .public) bytes)")
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

    // MARK: - Week navigation (Home Screen widget only)

    /// Which week the large Home Screen widget is currently showing: 0 = this
    /// week, negative = past weeks. Persisted in the shared suite so the
    /// timeline provider (a fresh process on every reload) can read it back.
    /// The app resets this to 0 whenever it pushes fresh data (see
    /// `pushUpdate`), so a stale "browsing last week" selection never lingers
    /// once real activity happens.
    static var selectedWeekOffset: Int {
        get { suite?.integer(forKey: selectedWeekOffsetKey) ?? 0 }
        set { suite?.set(newValue, forKey: selectedWeekOffsetKey) }
    }

    // MARK: - Pending action (widget button → app)

    /// Record a button tap so the app can apply it (the app owns persistence,
    /// Live Activity, and sync — the widget only signals).
    static func recordPendingAction(_ action: WidgetAction) {
        suite?.set(action.rawValue, forKey: pendingActionKey)
        postDarwinNotification()
    }

    /// Read + clear the pending action. Returns nil when nothing is pending.
    static func consumePendingAction() -> WidgetAction? {
        guard let raw = suite?.string(forKey: pendingActionKey),
              let action = WidgetAction(rawValue: raw) else { return nil }
        suite?.removeObject(forKey: pendingActionKey)
        return action
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
        guard let data = suite?.data(forKey: settingsKey) else {
            logger.notice("readSettings: no data at key '\(settingsKey, privacy: .public)' — returning defaults")
            return .empty
        }
        guard let settings = try? JSONDecoder().decode(WidgetSettings.self, from: data) else {
            logger.error("readSettings: found \(data.count, privacy: .public) bytes but failed to decode — returning defaults")
            return .empty
        }
        return settings
    }

    static func readSessions() -> [WidgetSession] {
        guard let data = suite?.data(forKey: sessionsKey) else {
            logger.notice("readSessions: no data at key '\(sessionsKey, privacy: .public)' — returning empty")
            return []
        }
        guard let sessions = try? JSONDecoder().decode([WidgetSession].self, from: data) else {
            logger.error("readSessions: found \(data.count, privacy: .public) bytes but failed to decode — returning empty")
            return []
        }
        logger.notice("readSessions: decoded \(sessions.count, privacy: .public) sessions")
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

    /// All sessions (open or completed) whose clock-in falls in the week `offset`
    /// weeks from the current one (0 = this week, -1 = last week, ...).
    static func weekSessions(
        from sessions: [WidgetSession],
        offset: Int = 0,
        calendar: Calendar = .current
    ) -> [WidgetSession] {
        guard let interval = weekInterval(offset: offset, calendar: calendar) else { return [] }
        return sessions.filter { $0.clockIn >= interval.start && $0.clockIn < interval.end }
    }

    /// The `DateInterval` for the week `offset` weeks from the current one.
    static func weekInterval(offset: Int, calendar: Calendar = .current) -> DateInterval? {
        guard let day = calendar.date(byAdding: .weekOfYear, value: offset, to: Date()) else { return nil }
        return calendar.dateInterval(of: .weekOfYear, for: day)
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