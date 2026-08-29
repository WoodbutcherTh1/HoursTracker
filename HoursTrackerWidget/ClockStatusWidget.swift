import WidgetKit
import SwiftUI

/// Lock Screen status widget. accessoryRectangular gets two explicit tap targets — Clock
/// In / Clock Out — via `Link(destination:)` to `hourstracker://clockIn` /
/// `hourstracker://clockOut`. accessoryCircular/accessoryInline are too small for two
/// separate targets, so they stay a single tap, but link to the state-correct action
/// (clockIn when showing "Out", clockOut when showing "In") rather than an app-side
/// toggle guess. Neither family mutates anything itself — see the note on this target
/// in project.yml for why interactivity is deliberately kept out of the widget process.
///
/// NOT verified against a real build — written without Xcode or a widget-enabled
/// simulator available in this environment.
struct ClockStatusWidget: Widget {
    let kind = "HoursTrackerClockStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClockStatusProvider()) { entry in
            ClockStatusWidgetView(entry: entry)
                // Required on iOS 17+ for every widget, accessory families included —
                // without it WidgetKit refuses to render the widget at all and shows a
                // broken "Please adopt containerBackground" placeholder instead (which is
                // exactly what showed up on the Lock Screen). `.clear` because accessory
                // widgets should let the system's own Lock Screen vibrancy/blur show
                // through rather than painting an opaque background.
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Clock Status")
        .description("Shows whether you're clocked in, with a button to clock in or out.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private let clockInURL = URL(string: "hourstracker://clockIn")!
private let clockOutURL = URL(string: "hourstracker://clockOut")!

private struct ClockStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClockStatusEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Link(destination: entry.isClockedIn ? clockOutURL : clockInURL) {
                if entry.isClockedIn, let since = entry.clockInDate {
                    Label {
                        Text(since, style: .timer)
                    } icon: {
                        Image(systemName: "clock.fill")
                    }
                } else {
                    Label("Clocked Out", systemImage: "clock")
                }
            }

        case .accessoryCircular:
            Link(destination: entry.isClockedIn ? clockOutURL : clockInURL) {
                VStack(spacing: 2) {
                    Image(systemName: entry.isClockedIn ? "clock.fill" : "clock")
                    Text(entry.isClockedIn ? "In" : "Out")
                        .font(.caption2.weight(.semibold))
                }
            }

        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.isClockedIn ? "Clocked In" : "Clocked Out")
                    .font(.headline)
                if entry.isClockedIn, let since = entry.clockInDate {
                    Text(since, style: .timer)
                        .font(.caption.monospacedDigit())
                } else {
                    Text("Tap a button below")
                        .font(.caption2)
                }
                HStack(spacing: 6) {
                    Link(destination: clockInURL) {
                        Text("In")
                            .font(.caption2.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(.white.opacity(entry.isClockedIn ? 0.08 : 0.22), in: Capsule())
                    }
                    Link(destination: clockOutURL) {
                        Text("Out")
                            .font(.caption2.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(.white.opacity(entry.isClockedIn ? 0.22 : 0.08), in: Capsule())
                    }
                }
            }
        }
    }
}
