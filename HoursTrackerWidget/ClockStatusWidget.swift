import WidgetKit
import SwiftUI

/// Lock Screen status widget. Tapping it opens the app via `hourstracker://clockToggle`
/// (set through `.widgetURL`) rather than mutating anything itself — see the note on
/// this target in project.yml for why interactivity is deliberately kept out of the
/// widget process.
///
/// NOT verified against a real build — written without Xcode or a widget-enabled
/// simulator available in this environment.
struct ClockStatusWidget: Widget {
    let kind = "HoursTrackerClockStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClockStatusProvider()) { entry in
            ClockStatusWidgetView(entry: entry)
                .widgetURL(URL(string: "hourstracker://clockToggle"))
                // Required on iOS 17+ for every widget, accessory families included —
                // without it WidgetKit refuses to render the widget at all and shows a
                // broken "Please adopt containerBackground" placeholder instead (which is
                // exactly what showed up on the Lock Screen). `.clear` because accessory
                // widgets should let the system's own Lock Screen vibrancy/blur show
                // through rather than painting an opaque background.
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Clock Status")
        .description("Shows whether you're clocked in, and opens HoursTracker to toggle it.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct ClockStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClockStatusEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            if entry.isClockedIn, let since = entry.clockInDate {
                Label {
                    Text(since, style: .timer)
                } icon: {
                    Image(systemName: "clock.fill")
                }
            } else {
                Label("Clocked Out", systemImage: "clock")
            }

        case .accessoryCircular:
            VStack(spacing: 2) {
                Image(systemName: entry.isClockedIn ? "clock.fill" : "clock")
                Text(entry.isClockedIn ? "In" : "Out")
                    .font(.caption2.weight(.semibold))
            }

        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isClockedIn ? "Clocked In" : "Clocked Out")
                    .font(.headline)
                if entry.isClockedIn, let since = entry.clockInDate {
                    Text(since, style: .timer)
                        .font(.caption.monospacedDigit())
                } else {
                    Text("Tap to clock in")
                        .font(.caption)
                }
            }
        }
    }
}
