#if DEBUG
import Foundation

/// Seeds a realistic, entirely fake dataset for App Store screenshot automation.
/// Only ever reachable behind the `UITEST_SCREENSHOTS` launch argument in a DEBUG
/// build (see `HoursTrackerUITests/ScreenshotTests.swift`), so it can never run in
/// a release build or a normal user session.
/// Design QA scenarios (`UITEST_QA_SCENARIO <name>`), layered on the standard demo:
/// - `standard`  — the App Store dataset (5-day / 42h goal).
/// - `shabbat`   — plus a 9h rest-day shift yesterday; its Day Summary opens (150%+, orange).
/// - `night`     — plus a 23:00 → 07:00 shift ending today; its Day Summary opens.
/// - `variesRateZero` — week pattern "varies" (no Today/Month bars) and rate 0.
/// - `newUser`   — no shifts, no name.
enum ScreenshotScenario: String {
    case standard, shabbat, night, variesRateZero, newUser

    static var current: ScreenshotScenario {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "UITEST_QA_SCENARIO"), args.indices.contains(index + 1) else {
            return .standard
        }
        return ScreenshotScenario(rawValue: args[index + 1]) ?? .standard
    }
}

extension AppViewModel {
    func seedDemoDataForScreenshots() {
        let scenario = ScreenshotScenario.current
        // Clean screens: no first-run hints over the screenshots.
        UserDefaults.standard.set(true, forKey: "homeStatsReorderHintDismissed")
        var settings = WorkplaceSettings.default
        settings.workplaceName = "Riverside Café"
        settings.workerFullName = "Alex Morgan"
        settings.employeeNumber = "EMP-2291"
        settings.hourlyRate = 55
        settings.dailyGasAllowance = 35
        settings.currencyCode = "ILS"
        settings.payrollStartDay = 1
        settings.modifiedAt = Date()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var sessions: [WorkSession] = []

        for offset in 1...30 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)

            // Saturday is the weekly rest day (matches `settings.restDayWeekday`).
            // Worked on two of them anyway, to show premium rest-day pay in the demo.
            let isRestDay = weekday == 7
            if isRestDay && offset % 10 != 0 { continue }

            let isLongDay = weekday == 5 // a longer Friday shift each week
            let hours: Double = isLongDay ? 9.5 : 8.5
            guard
                let clockIn = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day),
                let clockOut = calendar.date(byAdding: .minute, value: Int(hours * 60), to: clockIn)
            else { continue }

            sessions.append(
                WorkSession(
                    date: day,
                    clockIn: clockIn,
                    clockOut: clockOut,
                    dayType: isRestDay ? .restDay : .regular
                )
            )
        }

        var summaryClockIn: Date?
        switch scenario {
        case .standard:
            break
        case .shabbat:
            if let day = calendar.date(byAdding: .day, value: -1, to: today),
               let clockIn = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day),
               let clockOut = calendar.date(byAdding: .minute, value: 9 * 60, to: clockIn) {
                sessions.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
                sessions.append(WorkSession(date: day, clockIn: clockIn, clockOut: clockOut, dayType: .restDay))
                summaryClockIn = clockIn
            }
        case .night:
            // Payroll convention: the shift belongs to the day it started.
            if let day = calendar.date(byAdding: .day, value: -1, to: today),
               let clockIn = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day),
               let clockOut = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today) {
                sessions.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
                var shift = WorkSession(date: day, clockIn: clockIn, clockOut: clockOut, dayType: .regular)
                shift.isNightShift = WorkSession.qualifiesAsNightShift(clockIn: clockIn, clockOut: clockOut)
                sessions.append(shift)
                summaryClockIn = clockIn
            }
        case .variesRateZero:
            settings.hourlyRate = 0
            DisplayPreferences.shared.weekPattern = .varies
            DisplayPreferences.shared.weeklyGoalHoursDisplayOnly = 30
        case .newUser:
            sessions = []
            settings.workerFullName = ""
            DisplayPreferences.shared.weekPattern = nil
            DisplayPreferences.shared.weeklyGoalHoursDisplayOnly = nil
        }

        let document = FullDataExportDocument(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: "screenshot-seed",
            settings: settings,
            sessions: sessions,
            computedBreakdowns: [],
            activityLog: []
        )
        try? importFullDataExport(document, mode: .replace)

        if let summaryClockIn {
            presentDaySummaryForScreenshots(clockIn: summaryClockIn)
        }

        // App Store shots (`UITEST_CLOCKED_IN_MINUTES <n>`): a shift already running
        // for n minutes, so Home shows a realistic live timer and pay.
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "UITEST_CLOCKED_IN_MINUTES"), args.indices.contains(index + 1),
           let minutes = Double(args[index + 1]) {
            clockIn(at: Date().addingTimeInterval(-minutes * 60))
        }
    }
}
#endif
