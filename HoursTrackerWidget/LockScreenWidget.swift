import SwiftUI
import WidgetKit

/// Lock Screen widgets: the shift at a glance without unlocking.
///
/// - Rectangular: status, a live timer (paid time, or the break countdown) and
///   today's pay unless pay is hidden.
/// - Circular: progress toward the standard day, hours in the middle.
/// - Inline: one line above the clock.
///
/// Read-only on purpose — clock in/out and breaks stay one tap away in the Live
/// Activity and Home Screen widget, so nothing fires from a pocket tap. Tapping
/// opens the app on Home.
struct HoursLockScreenWidget: Widget {
    let kind = "HoursLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HoursTimelineProvider()) { entry in
            HoursLockScreenView(entry: entry)
                .environment(\.layoutDirection, WidgetL10n.layoutDirection)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "hourstracker://tab/home"))
        }
        .configurationDisplayName(WidgetL10n.displayName)
        .description(WidgetL10n.smallDescription)
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct HoursLockScreenView: View {
    let entry: HoursEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    // MARK: Rectangular

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let session = entry.session, entry.isOpen {
                Label {
                    Text(verbatim: session.isOnBreak ? WidgetL10n.onBreak : WidgetL10n.working)
                } icon: {
                    Image(systemName: session.isOnBreak ? "cup.and.saucer.fill" : "clock.fill")
                }
                .font(.caption.weight(.semibold))
                .widgetAccentable()

                timer(for: session)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)

                if !WidgetBridge.hidePay {
                    Text(verbatim: "\(pay(entry.estimatedPay + entry.todayCompletedPay)) \(WidgetL10n.today)")
                        .font(.caption)
                        .lineLimit(1)
                }
            } else {
                Label {
                    Text(verbatim: entry.todayCompletedHours > 0 ? WidgetL10n.shiftComplete : WidgetL10n.readyToWork)
                } icon: {
                    Image(systemName: entry.todayCompletedHours > 0 ? "checkmark.circle.fill" : "play.circle.fill")
                }
                .font(.caption.weight(.semibold))
                .widgetAccentable()

                Text(verbatim: "\(WidgetL10n.today): \(WidgetL10n.hoursShort(entry.todayCompletedHours))")
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)

                Text(verbatim: "\(WidgetL10n.thisWeek): \(WidgetL10n.hoursShort(entry.weeklyHours))")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Break countdown while on break, otherwise the paid clock (same source as
    /// the app), otherwise time since clock-in.
    @ViewBuilder
    private func timer(for session: WidgetSession) -> some View {
        if session.isOnBreak, let start = session.breakStart {
            let minutes = entry.settings.breakTargetMinutes ?? 30
            let end = start.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
            Text(timerInterval: min(start, end)...end, countsDown: true)
        } else if let curve = entry.livePay {
            Text(timerInterval: curve.paidClockStart...Date.distantFuture, countsDown: false)
        } else {
            Text(timerInterval: session.clockIn...Date.distantFuture, countsDown: false)
        }
    }

    // MARK: Circular

    private var circular: some View {
        let standard = max(entry.settings.standardDayHours, 1)
        let hours = entry.isOpen ? entry.elapsedHours : entry.todayCompletedHours
        return Gauge(value: min(hours, standard), in: 0...standard) {
            Image(systemName: entry.session?.isOnBreak == true ? "cup.and.saucer.fill" : "clock.fill")
        } currentValueLabel: {
            Text(verbatim: String(format: "%.1f", hours))
                .font(.system(.body, design: .rounded).weight(.bold))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    // MARK: Inline

    private var inline: some View {
        Group {
            if let session = entry.session, entry.isOpen {
                Label {
                    Text(verbatim: "\(session.isOnBreak ? WidgetL10n.onBreak : WidgetL10n.working) · \(WidgetL10n.hoursShort(entry.elapsedHours))")
                } icon: {
                    Image(systemName: session.isOnBreak ? "cup.and.saucer.fill" : "clock.fill")
                }
            } else {
                Label {
                    Text(verbatim: "\(WidgetL10n.today) \(WidgetL10n.hoursShort(entry.todayCompletedHours))")
                } icon: {
                    Image(systemName: "hourglass")
                }
            }
        }
    }

    private func pay(_ amount: Double) -> String {
        WidgetBridge.format(amount: amount, currencyCode: entry.settings.currencyCode)
    }
}
