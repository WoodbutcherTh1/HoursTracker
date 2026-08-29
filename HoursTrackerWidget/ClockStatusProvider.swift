import WidgetKit

/// Reads the App-Group snapshot the phone app writes (`WidgetStatusStore`). Read-only:
/// this extension never writes to the shared suite. If the App Group entitlement isn't
/// actually applied yet (see docs/HoursTracker.entitlements.appgroup.example),
/// `UserDefaults(suiteName:)` returns an empty, isolated store, so this degrades to the
/// "clocked out" placeholder rather than crashing or showing stale data.
///
/// NOT verified against a real build — written without Xcode or a widget-enabled
/// simulator available in this environment.
struct ClockStatusEntry: TimelineEntry {
    let date: Date
    let isClockedIn: Bool
    let clockInDate: Date?
}

struct ClockStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClockStatusEntry {
        ClockStatusEntry(date: Date(), isClockedIn: false, clockInDate: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClockStatusEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClockStatusEntry>) -> Void) {
        // `.never` — the phone explicitly reloads this widget's timeline on every
        // clock in/out via `WidgetCenter.shared.reloadTimelines`, so there is no
        // fixed refresh schedule to predict here.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> ClockStatusEntry {
        let defaults = UserDefaults(suiteName: WidgetStatusStore.appGroupID)
        let isClockedIn = defaults?.bool(forKey: "isClockedIn") ?? false
        let clockInDate: Date? = {
            guard isClockedIn, let interval = defaults?.object(forKey: "clockInDate") as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }()
        return ClockStatusEntry(date: Date(), isClockedIn: isClockedIn, clockInDate: clockInDate)
    }
}

/// Duplicated (not imported from the app target — widget extensions can't depend on
/// the host app module) rather than shared, since it is just two string constants.
enum WidgetStatusStore {
    static let appGroupID = "group.com.hourstracker.app"
}
