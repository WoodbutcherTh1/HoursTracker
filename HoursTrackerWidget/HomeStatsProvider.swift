import WidgetKit

/// Reads the richer App-Group snapshot `WidgetStatusStore.refresh` writes. Read-only,
/// same as `ClockStatusProvider` — see that file's header for the shared-suite
/// fallback behavior when the App Group entitlement isn't applied yet.
///
/// NOT verified against a real build — written without Xcode or a widget-enabled
/// simulator available in this environment.
struct HomeStatsEntry: TimelineEntry {
    let date: Date
    let isClockedIn: Bool
    let clockInDate: Date?
    let todayHours: Double
    let weekHours: Double
    let monthWorkedDays: Int
    let todayGrossPay: Double
    let currencyCode: String
}

struct HomeStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeStatsEntry {
        HomeStatsEntry(
            date: Date(), isClockedIn: false, clockInDate: nil,
            todayHours: 0, weekHours: 0, monthWorkedDays: 0,
            todayGrossPay: 0, currencyCode: "ILS"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeStatsEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeStatsEntry>) -> Void) {
        // `.never` — the phone reloads this widget's timeline whenever sessions or
        // settings change (WidgetStatusStore.refresh), so there's no schedule to predict.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> HomeStatsEntry {
        let defaults = UserDefaults(suiteName: WidgetStatusStore.appGroupID)
        let isClockedIn = defaults?.bool(forKey: "isClockedIn") ?? false
        let clockInDate: Date? = {
            guard isClockedIn, let interval = defaults?.object(forKey: "clockInDate") as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }()
        return HomeStatsEntry(
            date: Date(),
            isClockedIn: isClockedIn,
            clockInDate: clockInDate,
            todayHours: defaults?.object(forKey: "todayHours") as? Double ?? 0,
            weekHours: defaults?.object(forKey: "weekHours") as? Double ?? 0,
            monthWorkedDays: defaults?.object(forKey: "monthWorkedDays") as? Int ?? 0,
            todayGrossPay: defaults?.object(forKey: "todayGrossPay") as? Double ?? 0,
            currencyCode: defaults?.string(forKey: "currencyCode") ?? "ILS"
        )
    }
}
