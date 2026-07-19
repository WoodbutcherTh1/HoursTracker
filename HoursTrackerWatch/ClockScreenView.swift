import SwiftUI
import HoursTrackerKit

struct ClockScreenView: View {
    @ObservedObject var viewModel: WatchAppViewModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let locale = viewModel.locale
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { context in
            let now = context.date
            VStack(spacing: 6) {
                if let open = viewModel.activeSession {
                    Text(WatchL10n.elapsed(from: open.clockIn, now: now, locale: locale))
                        .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(
                            isLuminanceReduced
                                ? .secondary
                                : SharedHomeNeon.coral
                        )
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                } else {
                    Text(WatchL10n.clockTitle(locale: locale))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Same door component as iPhone Home (scaled for watch HIG).
                SharedClockDoorButton(
                    mode: viewModel.isClockedIn ? .clockOut : .clockIn,
                    title: viewModel.isClockedIn
                        ? WatchL10n.clockOut(locale: locale)
                        : WatchL10n.clockIn(locale: locale),
                    doorWidth: 56,
                    doorHeight: 66,
                    showTitle: true
                ) {
                    viewModel.toggleClock()
                }
                .accessibilityIdentifier("watch.clock.toggle")

                Text(todayLine(now: now, locale: locale))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(WatchL10n.clockTitle(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func todayLine(now: Date, locale: Locale) -> String {
        let hours = viewModel.todayHours(now: now)
        let pay = viewModel.todayGross(now: now)
        let hoursText = WatchL10n.hoursShort(hours, locale: locale)
        let money = PayFormatter.string(pay, currencyCode: viewModel.paySettings.currencyCode, locale: locale)
        return "\(WatchL10n.todaySummary(locale: locale)): \(hoursText) · \(money)"
    }
}
