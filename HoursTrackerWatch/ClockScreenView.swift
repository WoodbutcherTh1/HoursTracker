import SwiftUI
import HoursTrackerKit

struct ClockScreenView: View {
    @ObservedObject var viewModel: WatchAppViewModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let locale = viewModel.locale
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { context in
            let now = context.date
            VStack(spacing: 10) {
                if let open = viewModel.activeSession {
                    Text(WatchL10n.elapsed(from: open.clockIn, now: now, locale: locale))
                        .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(isLuminanceReduced ? .secondary : .primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                } else {
                    Text(WatchL10n.clockTitle(locale: locale))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.toggleClock()
                } label: {
                    Text(
                        viewModel.isClockedIn
                            ? WatchL10n.clockOut(locale: locale)
                            : WatchL10n.clockIn(locale: locale)
                    )
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isClockedIn ? .orange : .green)
                .accessibilityIdentifier("watch.clock.toggle")

                Text(todayLine(now: now, locale: locale))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
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
