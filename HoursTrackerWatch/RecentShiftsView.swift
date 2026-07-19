import SwiftUI
import HoursTrackerKit

struct RecentShiftsView: View {
    @ObservedObject var viewModel: WatchAppViewModel

    var body: some View {
        let locale = viewModel.locale
        let shifts = viewModel.recentCompletedShifts()
        Group {
            if shifts.isEmpty {
                Text(WatchL10n.recentEmpty(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shifts) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateText(session.date, locale: locale))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(detailLine(session, locale: locale))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .environment(\.layoutDirection, viewModel.layoutDirection)
                    .accessibilityIdentifier("watch.recent.row")
                }
            }
        }
        .navigationTitle(WatchL10n.recentTitle(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dateText(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(locale))
    }

    private func detailLine(_ session: WorkSession, locale: Locale) -> String {
        let hours = WatchL10n.hoursShort(session.totalHours, locale: locale)
        let gross = WatchGrossEstimate.breakdown(
            for: session,
            in: viewModel.sessions,
            paySettings: viewModel.paySettings
        ).totalPay
        let money = PayFormatter.string(
            gross,
            currencyCode: viewModel.paySettings.currencyCode,
            locale: locale
        )
        return "\(hours) · \(money)"
    }
}
