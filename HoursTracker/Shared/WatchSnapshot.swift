import Foundation

/// Snapshot of the phone's full app state sent to the paired Watch app over
/// WatchConnectivity. Kept fully precomputed (no raw session list beyond a small
/// windowed slice, no pay-calculation logic) so the Watch app has zero business
/// logic of its own — it only renders numbers the phone already produced with the
/// real `OvertimeCalculator`/`HistoryPeriodHelper`/`WorkedDaysCounter` (weekly OT
/// caps, tax estimate, payroll period math, etc.), not a simplified
/// re-implementation living on the watch.
///
/// This file is compiled into both the app target and the watch app target (see
/// project.yml) — it must stay free of iOS-only or watchOS-only imports.
struct WatchSnapshot: Codable, Equatable {
    // MARK: Clock state

    var isClockedIn: Bool
    var clockInTime: Date?

    // MARK: Home tab

    var todayHours: Double
    var todayNetPay: Double
    var todayGrossPay: Double
    var weekHours: Double
    var weekNetPay: Double
    var weekGrossPay: Double
    var monthShiftCount: Int
    var monthNetPay: Double
    var monthGrossPay: Double
    /// 7 values, starting from the locale's first weekday.
    var weekDailyHours: [Double]
    /// 7 single-letter weekday labels, same order as `weekDailyHours`.
    var weekDayLabels: [String]
    /// Index of today within `weekDailyHours`/`weekDayLabels`, if today is in this week.
    var todayWeekdayIndex: Int?
    /// Mirrors the phone's Home stat-card order (`HomeStatMetric` raw values) so the
    /// Watch shows cards in the same personalized order.
    var homeStatOrder: [String]

    // MARK: History tab

    /// Months away from the payroll period containing "now" (0 = current period).
    var historyPeriodOffset: Int
    var historyPeriodTitle: String
    var historyPeriodRangeLabel: String
    /// Every day in the active payroll period (no leading/trailing padding).
    var historyDays: [WatchHistoryDay]
    /// Sessions within the active payroll period, most recent first.
    var historySessions: [WatchHistorySession]
    var historyTotalHours: Double
    var historyTotalNetPay: Double
    var historyTotalGrossPay: Double
    var historyWorkedDayCount: Int
    /// Trailing 6 calendar months of hours/pay — same as the phone's monthly trend card.
    var historyTrend: [WatchTrendPoint]

    // MARK: Export tab

    var exportThisMonth: WatchExportPreview
    var exportThisYear: WatchExportPreview

    // MARK: Settings tab

    var settingsSummary: WatchSettingsSummary

    var currencyCode: String
    var workplaceName: String
    /// The phone's chosen Home accent color ("RRGGBB", no `#`) — see
    /// `HomeAccentTheme` — so the Watch's tint matches instead of the system default.
    var accentColorHex: String
    var generatedAt: Date

    static let empty = WatchSnapshot(
        isClockedIn: false,
        clockInTime: nil,
        todayHours: 0,
        todayNetPay: 0,
        todayGrossPay: 0,
        weekHours: 0,
        weekNetPay: 0,
        weekGrossPay: 0,
        monthShiftCount: 0,
        monthNetPay: 0,
        monthGrossPay: 0,
        weekDailyHours: Array(repeating: 0, count: 7),
        weekDayLabels: Array(repeating: "", count: 7),
        todayWeekdayIndex: nil,
        homeStatOrder: ["month", "week", "today"],
        historyPeriodOffset: 0,
        historyPeriodTitle: "",
        historyPeriodRangeLabel: "",
        historyDays: [],
        historySessions: [],
        historyTotalHours: 0,
        historyTotalNetPay: 0,
        historyTotalGrossPay: 0,
        historyWorkedDayCount: 0,
        historyTrend: [],
        exportThisMonth: .empty,
        exportThisYear: .empty,
        settingsSummary: .empty,
        currencyCode: "ILS",
        workplaceName: "",
        accentColorHex: "26F273",
        generatedAt: .distantPast
    )
}

struct WatchHistoryDay: Codable, Equatable, Identifiable {
    var date: Date
    var isToday: Bool
    var hasSession: Bool
    var netPay: Double?
    var grossPay: Double?
    var id: Date { date }
}

struct WatchHistorySession: Codable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var clockIn: Date
    var clockOut: Date?
    var hours: Double
    var netPay: Double
    var grossPay: Double
}

struct WatchTrendPoint: Codable, Equatable, Identifiable {
    var id: Date
    var label: String
    var hours: Double
    var pay: Double
}

struct WatchExportPreview: Codable, Equatable {
    var rangeLabel: String
    var dayCount: Int
    var totalHours: Double
    var gross: Double
    var net: Double
    var hasData: Bool

    static let empty = WatchExportPreview(
        rangeLabel: "", dayCount: 0, totalHours: 0, gross: 0, net: 0, hasData: false
    )
}

struct WatchSettingsSummary: Codable, Equatable {
    var workerFullName: String
    var workplaceName: String
    var hourlyRate: Double
    var currencyCode: String
    var dailyGasAllowance: Double
    var standardDayHours: Double
    var ot125HoursCap: Double
    var weeklyStandardHours: Double
    var weeklyOvertimeCapHours: Double
    var restDayName: String
    var secondRestDayName: String?
    var payrollStartDay: Int
    var payrollWindowLabel: String
    var maritalStatusName: String
    var hasChildren: Bool
    var numberOfChildren: Int
    var creditPoints: Double
    var appLockEnabled: Bool
    var hideWidgetPay: Bool
    var isCloudSyncSupported: Bool
    var isCloudSyncEnabled: Bool
    var cloudSyncStatusText: String
    var languageOptionRaw: String
    var languageOptions: [WatchLanguageOption]
    var appVersion: String

    static let empty = WatchSettingsSummary(
        workerFullName: "",
        workplaceName: "",
        hourlyRate: 0,
        currencyCode: "ILS",
        dailyGasAllowance: 0,
        standardDayHours: 8.6,
        ot125HoursCap: 2,
        weeklyStandardHours: 42,
        weeklyOvertimeCapHours: 12,
        restDayName: "",
        secondRestDayName: nil,
        payrollStartDay: 1,
        payrollWindowLabel: "",
        maritalStatusName: "",
        hasChildren: false,
        numberOfChildren: 0,
        creditPoints: 0,
        appLockEnabled: false,
        hideWidgetPay: false,
        isCloudSyncSupported: false,
        isCloudSyncEnabled: false,
        cloudSyncStatusText: "",
        languageOptionRaw: "system",
        languageOptions: [],
        appVersion: ""
    )
}

struct WatchLanguageOption: Codable, Equatable, Identifiable {
    var raw: String
    var label: String
    var id: String { raw }
}

// MARK: - Requests (Watch → phone)

/// Kinds of request the Watch app can send the phone. Every kind that changes
/// state replies with a fresh `WatchSnapshot`; `requestExport` replies with a
/// `WatchAck` instead, since it doesn't change anything the Watch renders.
enum WatchActionKind: String, Codable {
    case clockIn
    case clockOut
    /// `intValue` is the number of payroll periods to move (±1).
    case shiftHistoryPeriod
    /// `boolValue` is the new state.
    case toggleAppLock
    /// `boolValue` is the new state.
    case toggleHideWidgetPay
    /// `boolValue` is the new state.
    case toggleCloudSync
    /// `stringValue` is an `AppLanguageOption` raw value.
    case setLanguage
    /// `stringValue` is "thisMonth" or "thisYear".
    case requestExport
    /// No payload — asks the phone to reply with its current snapshot.
    case requestFullSnapshot
}

struct WatchRequest: Codable {
    var kind: WatchActionKind
    var intValue: Int?
    var boolValue: Bool?
    var stringValue: String?
}

struct WatchAck: Codable {
    var success: Bool
    var message: String?
}

/// Shared (de)serialization for WatchConnectivity messages, which only accept
/// property-list-compatible dictionary values — `Data` qualifies, raw `Codable`
/// structs don't.
enum WatchMessageKey {
    static let snapshot = "watchSnapshot"
    static let request = "watchRequest"
    static let ack = "watchAck"
}

extension WatchSnapshot {
    func asMessage() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [WatchMessageKey.snapshot: data]
    }

    static func from(message: [String: Any]) -> WatchSnapshot? {
        guard let data = message[WatchMessageKey.snapshot] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}

extension WatchRequest {
    func asMessage() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [WatchMessageKey.request: data]
    }

    static func from(message: [String: Any]) -> WatchRequest? {
        guard let data = message[WatchMessageKey.request] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchRequest.self, from: data)
    }
}

extension WatchAck {
    func asMessage() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [WatchMessageKey.ack: data]
    }

    static func from(message: [String: Any]) -> WatchAck? {
        guard let data = message[WatchMessageKey.ack] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchAck.self, from: data)
    }
}
