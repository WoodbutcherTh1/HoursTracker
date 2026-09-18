#if DEBUG
import Foundation

/// Seeds a realistic, entirely fake dataset for App Store screenshot automation.
/// Only ever reachable behind the `UITEST_SCREENSHOTS` launch argument in a DEBUG
/// build (see `HoursTrackerUITests/ScreenshotTests.swift`), so it can never run in
/// a release build or a normal user session.
extension AppViewModel {
    func seedDemoDataForScreenshots() {
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

        let document = FullDataExportDocument(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: "screenshot-seed",
            settings: settings,
            sessions: sessions,
            computedBreakdowns: [],
            activityLog: []
        )
        try? importFullDataExport(document, mode: .replace)
    }
}
#endif
