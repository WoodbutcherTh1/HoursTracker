import AppIntents
import HoursTrackerKit
import SwiftUI
import WidgetKit

struct HoursStatusEntry: TimelineEntry {
    let date: Date
    let isClockedIn: Bool
    let clockIn: Date?
    let todayHours: Double
    let currencyCode: String
}

struct HoursStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> HoursStatusEntry {
        demoEntry(now: .now, clockedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (HoursStatusEntry) -> Void) {
        if context.isPreview {
            completion(demoEntry(now: .now, clockedIn: true))
            return
        }
        completion(makeEntry(now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HoursStatusEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(now: now)
        let next = now.addingTimeInterval(entry.isClockedIn ? 60 : 15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry(now: Date) -> HoursStatusEntry {
        let snap = WatchSharedStore.loadSnapshot()
        let open = snap?.sessions.filter(\.isOpen).max { $0.clockIn < $1.clockIn }
        let cal = Calendar.current
        var hours = 0.0
        if let snap {
            let today = snap.sessions.filter { cal.isDate($0.date, inSameDayAs: now) }
            hours = today.filter { !$0.isOpen }.reduce(0.0) { $0 + $1.totalHours }
            if let open, cal.isDate(open.date, inSameDayAs: now) {
                hours += max(0, now.timeIntervalSince(open.clockIn) / 3600)
            }
        }
        return HoursStatusEntry(
            date: now,
            isClockedIn: open != nil,
            clockIn: open?.clockIn,
            todayHours: hours,
            currencyCode: snap?.paySettings.currencyCode ?? "ILS"
        )
    }

    /// Preview / placeholder only — never written to App Group.
    private func demoEntry(now: Date, clockedIn: Bool) -> HoursStatusEntry {
        HoursStatusEntry(
            date: now,
            isClockedIn: clockedIn,
            clockIn: clockedIn ? now.addingTimeInterval(-2.5 * 3600) : nil,
            todayHours: clockedIn ? 2.5 : 7.25,
            currencyCode: "ILS"
        )
    }
}

struct HoursStatusWidget: Widget {
    let kind = "HoursStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HoursStatusProvider()) { entry in
            HoursStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.12, blue: 0.18),
                            Color(red: 0.12, green: 0.22, blue: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("HoursTracker")
        .description("Clock in/out and quick export.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HoursStatusWidgetView: View {
    var entry: HoursStatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HoursTracker")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
            Text(entry.isClockedIn ? "Clocked In" : "Clocked Out")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
            if entry.isClockedIn, let start = entry.clockIn {
                Text(elapsed(from: start, now: entry.date))
                    .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color(red: 0.45, green: 0.88, blue: 0.72))
            } else {
                Text(formatHours(entry.todayHours))
                    .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Button(intent: ToggleClockIntent()) {
                Label(
                    entry.isClockedIn ? "Clock Out" : "Clock In",
                    systemImage: entry.isClockedIn ? "stop.fill" : "play.fill"
                )
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .tint(entry.isClockedIn ? Color.orange : Color(red: 0.35, green: 0.78, blue: 0.62))
        }
        .padding(4)
    }

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HoursTracker")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(entry.isClockedIn ? "On shift" : "Off shift")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                if entry.isClockedIn, let start = entry.clockIn {
                    Text(elapsed(from: start, now: entry.date))
                        .font(.system(.title, design: .rounded).monospacedDigit().weight(.bold))
                        .foregroundStyle(Color(red: 0.45, green: 0.88, blue: 0.72))
                }
                Text("Today \(formatHours(entry.todayHours))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button(intent: ToggleClockIntent()) {
                    Label(
                        entry.isClockedIn ? "Out" : "In",
                        systemImage: entry.isClockedIn ? "stop.fill" : "play.fill"
                    )
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .tint(entry.isClockedIn ? Color.orange : Color(red: 0.35, green: 0.78, blue: 0.62))

                Button(intent: QuickExportIntent()) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Color(red: 0.40, green: 0.62, blue: 0.95))
            }
            .frame(width: 110)
        }
        .padding(4)
    }

    private func elapsed(from start: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    private func formatHours(_ value: Double) -> String {
        String(format: "%.1fh", value)
    }
}

#Preview("Small demo", as: .systemSmall) {
    HoursStatusWidget()
} timeline: {
    HoursStatusEntry(
        date: .now,
        isClockedIn: true,
        clockIn: Date().addingTimeInterval(-5400),
        todayHours: 1.5,
        currencyCode: "ILS"
    )
}

#Preview("Medium demo", as: .systemMedium) {
    HoursStatusWidget()
} timeline: {
    HoursStatusEntry(
        date: .now,
        isClockedIn: false,
        clockIn: nil,
        todayHours: 8.6,
        currencyCode: "ILS"
    )
}
