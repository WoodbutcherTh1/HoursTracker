import Foundation

/// Deterministic sample data for App Store screenshots.
/// Enabled only when `HT_SCREENSHOT_MODE=1` (never on by default).
public enum WatchScreenshotDemoData {
    public static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["HT_SCREENSHOT_MODE"] == "1" { return true }
        // Lang alone also arms screenshot mode (UITest always sets both).
        if let lang = env["HT_SCREENSHOT_LANG"], !lang.isEmpty { return true }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("HT_SCREENSHOT_MODE=1") { return true }
        if args.contains(where: { $0.hasPrefix("HT_SCREENSHOT_LANG=") }) { return true }
        return false
    }

    /// Preferred language for screenshot mode (`HT_SCREENSHOT_LANG=en|he|ar`).
    public static var preferredLanguage: WatchLanguageCode {
        let raw = ProcessInfo.processInfo.environment["HT_SCREENSHOT_LANG"]
            ?? ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("HT_SCREENSHOT_LANG=") })?
                .split(separator: "=").last.map(String.init)
        if let raw, !raw.isEmpty {
            return language(fromLocaleIdentifier: raw)
        }
        return language(fromLocaleIdentifier: Locale.autoupdatingCurrent.identifier)
    }

    /// Mid-shift open session + a few completed shifts (gross-only pay settings).
    public static func makeSnapshot(
        language: WatchLanguageCode = .english,
        now: Date = Date()
    ) -> WatchSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!

        func time(_ day: Date, hour: Int, minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        // Always start the open shift in the past relative to `now` so screenshot
        // mode shows the live timer + Clock Out (not a future clock-in).
        let openClockIn = now.addingTimeInterval(-3 * 3600 - 14 * 60)
        let open = WorkSession(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            date: cal.startOfDay(for: openClockIn),
            clockIn: openClockIn,
            clockOut: nil,
            isManualEntry: false,
            dayType: .regular
        )
        let s1 = WorkSession(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            date: yesterday,
            clockIn: time(yesterday, hour: 7, minute: 55),
            clockOut: time(yesterday, hour: 16, minute: 40),
            dayType: .regular
        )
        let s2 = WorkSession(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            date: twoDaysAgo,
            clockIn: time(twoDaysAgo, hour: 8, minute: 0),
            clockOut: time(twoDaysAgo, hour: 18, minute: 15),
            dayType: .regular
        )
        let s3 = WorkSession(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            date: threeDaysAgo,
            clockIn: time(threeDaysAgo, hour: 9, minute: 0),
            clockOut: time(threeDaysAgo, hour: 14, minute: 30),
            dayType: .restDay
        )

        let pay = WatchPaySettings(
            hourlyRate: 48,
            dailyGasAllowance: 35,
            standardDayHours: 8.6,
            ot125HoursCap: 2,
            nightStandardDayHours: 7,
            defaultBreakMinutes: 0,
            restDayWeekday: 7,
            secondRestDayWeekday: nil,
            currencyCode: "ILS",
            language: language
        )

        return WatchSnapshot(
            sessions: [open, s1, s2, s3],
            paySettings: pay,
            updatedAt: now
        )
    }

    public static func language(fromLocaleIdentifier id: String) -> WatchLanguageCode {
        let lower = id.lowercased()
        if lower.hasPrefix("he") { return .hebrew }
        if lower.hasPrefix("ar") { return .arabic }
        if lower.hasPrefix("en") { return .english }
        return .system
    }
}
