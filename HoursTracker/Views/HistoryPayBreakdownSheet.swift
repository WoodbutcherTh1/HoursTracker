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
    /// Holiday / vacation / recuperation / sick day counts for the same range.
    var dayCounts = PeriodDayCounts()
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

                    dayCountsCard
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

    /// ימי חג / ימי חופש / ימי הבראה / ימי מחלה — counts only.
    private var dayCountsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.dayCountsTitle)
                .font(.headline)
            dayCountRow(L10n.dayCountsHoliday, count: dayCounts.holiday, icon: "star.fill", tint: .yellow)
            dayCountRow(L10n.dayCountsVacation, count: dayCounts.vacation, icon: LeaveKind.vacation.systemImage, tint: .teal)
            dayCountRow(
                L10n.dayCountsRecuperation,
                count: dayCounts.recuperation,
                icon: LeaveKind.recuperation.systemImage,
                tint: .green
            )
            dayCountRow(L10n.dayCountsSick, count: dayCounts.sick, icon: "cross.case.fill", tint: .pink)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("history.dayCounts")
    }

    private func dayCountRow(_ label: String, count: Int, icon: String, tint: Color) -> some View {
        HStack {
            Label {
                Text(label)
                    .font(.subheadline)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            Spacer()
            Text(verbatim: "\(count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
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
