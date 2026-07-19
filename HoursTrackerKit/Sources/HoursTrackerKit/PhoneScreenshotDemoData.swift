import Foundation

/// Deterministic fake data for iPhone App Store screenshots / App Preview.
/// Armed only via `HT_SCREENSHOT_MODE` / `HT_SCREENSHOT_LANG` (same gates as Watch).
/// Never contains real worker PII — names are generic guests only.
public enum PhoneScreenshotDemoData {
    public static var isEnabled: Bool { WatchScreenshotDemoData.isEnabled }

    public static var preferredLanguage: WatchLanguageCode {
        WatchScreenshotDemoData.preferredLanguage
    }

    public struct DemoState: Sendable {
        public var sessions: [WorkSession]
        public var settings: WorkplaceSettings
    }

    /// Whether marketing Home should show an active (clocked-in) shift.
    /// Set `HT_SCREENSHOT_HOME_ACTIVE=1` (env or launch arg).
    public static var includeActiveShift: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["HT_SCREENSHOT_HOME_ACTIVE"] == "1" { return true }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("HT_SCREENSHOT_HOME_ACTIVE=1") { return true }
        return false
    }

    /// Demo Home/History/Export/Settings data. Guest name only — never real PII.
    /// Pass `includeActiveShift: true` (or env) for a live Clock Out / timer Home.
    public static func makeDemo(
        now: Date = Date(),
        includeActiveShift: Bool? = nil
    ) -> DemoState {
        let language = preferredLanguage
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let wantOpen = includeActiveShift ?? Self.includeActiveShift

        func time(_ day: Date, hour: Int, minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        func dayOffset(_ days: Int) -> Date {
            cal.date(byAdding: .day, value: days, to: today)!
        }

        // Rich History demo: 6 recent days with varied hours + 3 shifts on the
        // primary day (−1) so the day list isn't a single sparse row.
        let templates: [(offset: Int, inH: Int, inM: Int, outH: Int, outM: Int, dayType: DayType, id: String)] = [
            // Primary day (−1): three completed shifts
            (-1, 7, 0, 11, 15, .regular, "B1000000-0000-4000-8000-000000000011"),
            (-1, 12, 0, 16, 30, .regular, "B1000000-0000-4000-8000-000000000012"),
            (-1, 17, 0, 19, 45, .regular, "B1000000-0000-4000-8000-000000000013"),
            // Five more days with varied lengths
            (-2, 8, 0, 18, 15, .regular, "B1000000-0000-4000-8000-000000000002"),
            (-3, 8, 10, 17, 5, .regular, "B1000000-0000-4000-8000-000000000003"),
            (-4, 7, 45, 16, 20, .regular, "B1000000-0000-4000-8000-000000000004"),
            (-5, 9, 0, 14, 30, .restDay, "B1000000-0000-4000-8000-000000000005"),
            (-6, 8, 5, 17, 50, .regular, "B1000000-0000-4000-8000-000000000006"),
            // Extra depth for month totals / chart
            (-7, 8, 0, 16, 0, .regular, "B1000000-0000-4000-8000-000000000007"),
            (-8, 7, 50, 16, 35, .regular, "B1000000-0000-4000-8000-000000000008"),
            (-9, 8, 15, 18, 0, .regular, "B1000000-0000-4000-8000-000000000009"),
            (-10, 8, 0, 16, 45, .regular, "B1000000-0000-4000-8000-00000000000A"),
        ]

        var sessions: [WorkSession] = []
        if wantOpen {
            let openClockIn = now.addingTimeInterval(-3 * 3600 - 14 * 60)
            sessions.append(
                WorkSession(
                    id: UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!,
                    date: cal.startOfDay(for: openClockIn),
                    clockIn: openClockIn,
                    clockOut: nil,
                    isManualEntry: false,
                    dayType: .regular
                )
            )
        }
        for t in templates {
            let day = dayOffset(t.offset)
            sessions.append(
                WorkSession(
                    id: UUID(uuidString: t.id)!,
                    date: day,
                    clockIn: time(day, hour: t.inH, minute: t.inM),
                    clockOut: time(day, hour: t.outH, minute: t.outM),
                    isManualEntry: false,
                    dayType: t.dayType
                )
            )
        }

        var settings = WorkplaceSettings.default
        settings.workerFullName = guestName(for: language)
        settings.workerIDNumber = ""
        settings.employeeNumber = "DEMO-001"
        settings.workplaceName = workplaceName(for: language)
        settings.hourlyRate = 48
        settings.dailyGasAllowance = 35
        settings.currencyCode = "ILS"
        settings.arrivalRemindersEnabled = false
        settings.locationLatitude = nil
        settings.locationLongitude = nil
        settings.modifiedAt = now

        return DemoState(sessions: sessions, settings: settings)
    }

    public static func guestName(for language: WatchLanguageCode) -> String {
        switch language {
        case .hebrew: return "אורח"
        case .arabic: return "ضيف"
        case .english, .system: return "Guest"
        }
    }

    public static func workplaceName(for language: WatchLanguageCode) -> String {
        switch language {
        case .hebrew: return "מקום עבודה לדוגמה"
        case .arabic: return "مكان عمل تجريبي"
        case .english, .system: return "Demo Workplace"
        }
    }
}
