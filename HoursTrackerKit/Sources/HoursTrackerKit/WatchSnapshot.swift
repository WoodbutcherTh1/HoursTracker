import Foundation

/// Language preference mirrored from the iPhone — watch must not pick its own.
public enum WatchLanguageCode: String, Codable, Equatable, CaseIterable, Sendable {
    case system
    case english
    case hebrew
    case arabic
}

/// Pay settings safe to send to the watch. **Never** includes Israeli ID,
/// tax/marital status, geofence coordinates, or worker PII.
public struct WatchPaySettings: Codable, Equatable, Sendable {
    public var hourlyRate: Double
    public var dailyGasAllowance: Double
    public var standardDayHours: Double
    public var ot125HoursCap: Double
    public var nightStandardDayHours: Double
    public var defaultBreakMinutes: Int
    public var restDayWeekday: Int
    public var secondRestDayWeekday: Int?
    public var currencyCode: String
    public var language: WatchLanguageCode

    public init(
        hourlyRate: Double,
        dailyGasAllowance: Double,
        standardDayHours: Double,
        ot125HoursCap: Double,
        nightStandardDayHours: Double,
        defaultBreakMinutes: Int,
        restDayWeekday: Int,
        secondRestDayWeekday: Int?,
        currencyCode: String,
        language: WatchLanguageCode
    ) {
        self.hourlyRate = hourlyRate
        self.dailyGasAllowance = dailyGasAllowance
        self.standardDayHours = standardDayHours
        self.ot125HoursCap = ot125HoursCap
        self.nightStandardDayHours = nightStandardDayHours
        self.defaultBreakMinutes = defaultBreakMinutes
        self.restDayWeekday = restDayWeekday
        self.secondRestDayWeekday = secondRestDayWeekday
        self.currencyCode = currencyCode
        self.language = language
    }

    /// Build from full iPhone settings — strips ID/tax/location/PII by construction.
    public init(from settings: WorkplaceSettings, language: WatchLanguageCode) {
        self.init(
            hourlyRate: settings.hourlyRate,
            dailyGasAllowance: settings.dailyGasAllowance,
            standardDayHours: settings.standardDayHours,
            ot125HoursCap: settings.ot125HoursCap,
            nightStandardDayHours: settings.nightStandardDayHours,
            defaultBreakMinutes: settings.defaultBreakMinutes,
            restDayWeekday: settings.restDayWeekday,
            secondRestDayWeekday: settings.secondRestDayWeekday,
            currencyCode: settings.currencyCode,
            language: language
        )
    }

    /// Minimal `WorkplaceSettings` for gross-only `OvertimeCalculator` calls.
    public func workplaceSettingsForGrossEstimate() -> WorkplaceSettings {
        var s = WorkplaceSettings.default
        s.hourlyRate = hourlyRate
        s.dailyGasAllowance = dailyGasAllowance
        s.standardDayHours = standardDayHours
        s.ot125HoursCap = ot125HoursCap
        s.nightStandardDayHours = nightStandardDayHours
        s.defaultBreakMinutes = defaultBreakMinutes
        s.restDayWeekday = restDayWeekday
        s.secondRestDayWeekday = secondRestDayWeekday
        s.currencyCode = currencyCode
        s.workerIDNumber = ""
        s.workerFullName = ""
        s.locationLatitude = nil
        s.locationLongitude = nil
        s.arrivalRemindersEnabled = false
        return s
    }
}

/// Canonical snapshot pushed iPhone → Watch (and cached locally on watch).
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public var sessions: [WorkSession]
    public var paySettings: WatchPaySettings
    public var updatedAt: Date

    public init(sessions: [WorkSession], paySettings: WatchPaySettings, updatedAt: Date = Date()) {
        self.sessions = sessions
        self.paySettings = paySettings
        self.updatedAt = updatedAt
    }
}

/// Watch-side gross estimate helpers. Uses shared `OvertimeCalculator` math;
/// UI must display `totalPay` (gross), never `netPay`.
public enum WatchGrossEstimate {
    public static func todaySessions(
        from sessions: [WorkSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkSession] {
        sessions.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    public static func todayGross(
        sessions: [WorkSession],
        paySettings: WatchPaySettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DayPayBreakdown {
        let today = todaySessions(from: sessions, now: now, calendar: calendar)
            .filter { !$0.isOpen }
        let settings = paySettings.workplaceSettingsForGrossEstimate()
        return OvertimeCalculator.aggregate(sessions: today, settings: settings)
    }

    public static func breakdown(
        for session: WorkSession,
        in allSessions: [WorkSession],
        paySettings: WatchPaySettings
    ) -> DayPayBreakdown {
        OvertimeCalculator.breakdown(
            for: session,
            in: allSessions,
            settings: paySettings.workplaceSettingsForGrossEstimate()
        )
    }
}
