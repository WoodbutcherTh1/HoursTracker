import WidgetKit
import SwiftUI

/// Home Screen widget — unlike the Lock Screen `ClockStatusWidget`, this one renders in
/// full color, so it reuses the app's own green brand accent. Mirrors the three Home tab
/// stat cards (Today / Week / This Month) plus live clock status, since-when, and
/// today's running pay. The whole widget is one tap target that opens the app via
/// `hourstracker://clockToggle` — see the note on `HoursTrackerWidget` in project.yml
/// for why this isn't an in-widget AppIntent mutation.
///
/// NOT verified against a real build — written without Xcode or a widget-enabled
/// simulator available in this environment.
struct HomeStatsWidget: Widget {
    let kind = "HoursTrackerHomeStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeStatsProvider()) { entry in
            HomeStatsWidgetView(entry: entry)
                .widgetURL(URL(string: "hourstracker://clockToggle"))
                .containerBackground(Color(red: 0.09, green: 0.10, blue: 0.12), for: .widget)
        }
        .configurationDisplayName("HoursTracker")
        .description("Today / week / month at a glance, plus one tap to clock in or out.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private let accent = Color(red: 0.15, green: 0.95, blue: 0.45)

private struct HomeStatsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HomeStatsEntry

    private var currencyFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = entry.currencyCode
        f.maximumFractionDigits = 0
        return f
    }

    private var payText: String {
        currencyFormatter.string(from: entry.todayGrossPay as NSNumber) ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow
            Divider().overlay(Color.white.opacity(0.12))
            if family == .systemMedium {
                HStack(spacing: 6) {
                    tile(label: "Today", value: hours(entry.todayHours))
                    tile(label: "Week", value: hours(entry.weekHours))
                    tile(label: "Month", value: "\(entry.monthWorkedDays)d")
                }
            } else {
                tile(label: "Today", value: hours(entry.todayHours))
            }
        }
        .padding(12)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.isClockedIn ? "clock.fill" : "clock")
                .foregroundStyle(accent)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.isClockedIn ? "Clocked In" : "Clocked Out")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                if entry.isClockedIn, let since = entry.clockInDate {
                    Text(since, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("≈\(payText) today")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            if entry.isClockedIn {
                Text(payText)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(accent)
            }
        }
    }

    private func tile(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func hours(_ value: Double) -> String {
        let h = Int(value)
        let m = Int((value - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }
}
