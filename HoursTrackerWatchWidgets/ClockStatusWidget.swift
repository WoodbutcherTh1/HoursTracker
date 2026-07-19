import AppIntents
import HoursTrackerKit
import SwiftUI
import WidgetKit

/// Deep-link into the watch Clock screen (tap outside the button).
enum WatchDeepLink {
    static let clock = URL(string: "hourstracker-watch://clock")!
}

struct ClockStatusEntry: TimelineEntry {
    let date: Date
    let isClockedIn: Bool
    let clockIn: Date?
    let currencyCode: String
}

struct ClockStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClockStatusEntry {
        ClockStatusEntry(date: .now, isClockedIn: true, clockIn: Date().addingTimeInterval(-3600), currencyCode: "ILS")
    }

    func getSnapshot(in context: Context, completion: @escaping (ClockStatusEntry) -> Void) {
        completion(makeEntry(now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClockStatusEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(now: now)
        // Refresh every minute while clocked in so elapsed time stays honest.
        let next = now.addingTimeInterval(entry.isClockedIn ? 60 : 15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry(now: Date) -> ClockStatusEntry {
        let snap = WatchSharedStore.loadSnapshot()
        let open = snap?.sessions.filter(\.isOpen).max { $0.clockIn < $1.clockIn }
        return ClockStatusEntry(
            date: now,
            isClockedIn: open != nil,
            clockIn: open?.clockIn,
            currencyCode: snap?.paySettings.currencyCode ?? "ILS"
        )
    }
}

struct ClockStatusWidget: Widget {
    let kind = "ClockStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClockStatusProvider()) { entry in
            ClockStatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HoursTracker")
        .description("Clock status at a glance.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct ClockStatusWidgetView: View {
    var entry: ClockStatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Button(intent: ToggleClockIntent()) {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 1) {
                            Image(systemName: entry.isClockedIn ? "checkmark.circle.fill" : "clock")
                                .font(.title3)
                            if entry.isClockedIn, let start = entry.clockIn {
                                Text(elapsed(from: start, now: entry.date))
                                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                                    .minimumScaleFactor(0.6)
                            } else {
                                Text("Out")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            case .accessoryRectangular, .accessoryInline, .accessoryCorner:
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.isClockedIn ? "Clocked In" : "Clocked Out")
                        .font(.headline)
                    if entry.isClockedIn, let start = entry.clockIn {
                        Text(elapsed(from: start, now: entry.date))
                            .font(.system(.body, design: .rounded).monospacedDigit())
                    } else {
                        Text("Tap to clock in")
                            .font(.caption2)
                    }
                    Button(intent: ToggleClockIntent()) {
                        Text(entry.isClockedIn ? "Clock Out" : "Clock In")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            default:
                Button(intent: ToggleClockIntent()) {
                    Text(entry.isClockedIn ? "In" : "Out")
                }
                .buttonStyle(.plain)
            }
        }
        .widgetURL(WatchDeepLink.clock)
    }

    private func elapsed(from start: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return String(format: "%d:%02d", h, m) }
        return String(format: "%dm", m)
    }
}

#Preview(as: .accessoryCircular) {
    ClockStatusWidget()
} timeline: {
    // Demo data only — not live payroll.
    ClockStatusEntry(date: .now, isClockedIn: true, clockIn: Date().addingTimeInterval(-5400), currencyCode: "ILS")
}
