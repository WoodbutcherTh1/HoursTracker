import SwiftUI

/// Pay breakdown popup for the History tab's sticky summary bar — total regular /
/// 125% / 150% hours plus gross and net pay for whatever period is currently shown
/// (full payroll period, or a single selected day).
struct HistoryPayBreakdownSheet: View {
    let breakdown: DayPayBreakdown
    /// Mirrors the summary bar's figure — same `WorkedDaysCounter` values, passed in
    /// rather than recomputed, so the two can't disagree.
    var workedDayCount: Int = 0
    var showsPendingWorkedDay: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                        .padding(.top, 4)

                    VStack(spacing: 12) {
                        summaryRow(L10n.summaryRegular, value: L10n.hoursLong(breakdown.regularHours))
                        summaryRow(L10n.summaryOT125, value: L10n.hoursLong(breakdown.ot125Hours))
                        summaryRow(L10n.summaryOT150, value: L10n.hoursLong(breakdown.ot150Hours))
                        Divider()
                        summaryRow(
                            L10n.historyTotalHours,
                            value: HistoryPeriodHelper.formatHoursClock(breakdown.totalHours),
                            bold: true
                        )
                        HStack {
                            Text(L10n.historyDaysWorked)
                                .font(.subheadline)
                            Spacer()
                            WorkedDaysBadge(
                                dayCount: workedDayCount,
                                showsPendingDay: showsPendingWorkedDay,
                                valueFont: .subheadline.monospacedDigit(),
                                showsTitle: false
                            )
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    GrossNetBadge(breakdown: breakdown)
                        .padding(.horizontal)

                    TaxDeductionsCard(breakdown: breakdown)
                        .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle(L10n.historyPayBreakdownTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.summaryDone) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func summaryRow(_ label: String, value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .headline : .subheadline)
            Spacer()
            Text(value)
                .font(bold ? .headline : .subheadline)
                .monospacedDigit()
        }
    }
}
