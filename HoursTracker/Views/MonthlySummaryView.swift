import SwiftUI
import Charts

/// Cross-month trend view — History itself only shows one payroll period at a time
/// (chevron-navigated), so this is the only place hours/pay are visible as a chart
/// across several months instead of exported to a file first.
struct MonthlySummaryView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss

    /// How many trailing calendar months to chart, oldest first.
    private let monthCount = 6

    private struct MonthPoint: Identifiable {
        let id: Date
        let label: String
        let breakdown: DayPayBreakdown
    }

    private var months: [MonthPoint] {
        let calendar = Calendar.current
        let now = Date()
        let labelFormatter: DateFormatter = {
            let f = AppLocale.makeDateFormatter()
            f.dateFormat = "MMM"
            return f
        }()

        return (0..<monthCount).reversed().compactMap { offset -> MonthPoint? in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let components = calendar.dateComponents([.year, .month], from: monthDate)
            guard let year = components.year, let month = components.month else { return nil }

            let sessions = viewModel.sessions.filter {
                $0.clockOut != nil
                    && calendar.component(.year, from: $0.date) == year
                    && calendar.component(.month, from: $0.date) == month
            }
            let breakdown = OvertimeCalculator.aggregate(sessions: sessions, settings: viewModel.settings)
            return MonthPoint(id: monthDate, label: labelFormatter.string(from: monthDate), breakdown: breakdown)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    chartCard(title: L10n.historyMonthlySummaryHoursChart) {
                        Chart(months) { point in
                            BarMark(
                                x: .value("month", point.label),
                                y: .value("hours", point.breakdown.regularHours)
                            )
                            .foregroundStyle(by: .value("type", L10n.summaryRegular))

                            BarMark(
                                x: .value("month", point.label),
                                y: .value("hours", point.breakdown.ot125Hours)
                            )
                            .foregroundStyle(by: .value("type", L10n.summaryOT125))

                            BarMark(
                                x: .value("month", point.label),
                                y: .value("hours", point.breakdown.ot150Hours)
                            )
                            .foregroundStyle(by: .value("type", L10n.summaryOT150))
                        }
                        .chartForegroundStyleScale([
                            L10n.summaryRegular: theme.accent,
                            L10n.summaryOT125: theme.accent.opacity(0.6),
                            L10n.summaryOT150: Color.orange
                        ])
                        .frame(height: 220)
                    }

                    chartCard(title: L10n.historyMonthlySummaryPayChart) {
                        Chart(months) { point in
                            BarMark(
                                x: .value("month", point.label),
                                y: .value("pay", point.breakdown.grossPay)
                            )
                            .foregroundStyle(theme.accent.gradient)
                        }
                        .frame(height: 180)
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(appBackground.background.ignoresSafeArea())
            .navigationTitle(L10n.historyMonthlySummaryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.summaryDone) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func chartCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
