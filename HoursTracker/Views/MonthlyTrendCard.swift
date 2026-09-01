import Charts
import SwiftUI

/// A single month's aggregate for the trend chart.
private struct MonthlyTrendPoint: Identifiable {
    let id: Date          // month start, used as the identity + sort key
    let label: String
    let hours: Double
    let pay: Double
}

/// "Monthly summary" card for the History screen: last six months of hours
/// as a teal bar chart, with average monthly pay in the footer. Uses the same
/// `OvertimeCalculator.aggregate` engine as the rest of the app, so weekly OT
/// caps and gas allowances are included.
struct MonthlyTrendCard: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var appLanguage: AppLanguageController
    @ObservedObject private var homeTheme = HomeAccentTheme.shared

    private var points: [MonthlyTrendPoint] {
        let calendar = Calendar.current
        var months: [Date] = []
        let now = Date()
        for offset in (0..<6).reversed() {
            if let month = calendar.date(byAdding: .month, value: -offset, to: now) {
                months.append(month)
            }
        }
        let formatter = Date.FormatStyle()
            .month(.abbreviated)
            .locale(appLanguage.locale)

        return months.compactMap { monthStart in
            let interval = calendar.dateInterval(of: .month, for: monthStart)
            let monthSessions = viewModel.sessions.filter { session in
                guard let interval else { return false }
                return session.clockOut != nil
                    && session.clockIn >= interval.start
                    && session.clockIn < interval.end
            }
            guard !monthSessions.isEmpty else {
                return MonthlyTrendPoint(id: monthStart, label: formatter.format(monthStart), hours: 0, pay: 0)
            }
            let hours = monthSessions.reduce(0) { $0 + $1.effectiveHours }
            let breakdown = OvertimeCalculator.aggregate(
                sessions: monthSessions,
                settings: viewModel.settings
            )
            return MonthlyTrendPoint(
                id: monthStart,
                label: formatter.format(monthStart),
                hours: hours,
                pay: breakdown.totalPay
            )
        }
    }

    private var averageMonthlyPay: Double {
        let paid = points.filter { $0.pay > 0 }
        guard !paid.isEmpty else { return 0 }
        return paid.reduce(0) { $0 + $1.pay } / Double(paid.count)
    }

    private var maxHours: Double {
        max(points.map(\.hours).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(homeTheme.accent)
                Text(L10n.historyMonthlyTrend.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .tracking(0.6)
                Spacer()
                Text(L10n.historyTrendHours)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }

            Chart(points) { point in
                BarMark(
                    x: .value("Month", point.label),
                    y: .value("Hours", point.hours)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            homeTheme.accent.opacity(0.95),
                            Color.cyan.opacity(point.hours >= maxHours * 0.9 ? 1 : 0.55),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(4)
                .annotation(position: .top) {
                    if point.hours > 0 {
                        Text(String(format: "%.0f", point.hours))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .frame(height: 120)
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                    AxisValueLabel()
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 10) {
                trendFootStat(
                    icon: "calendar",
                    value: L10n.historyTrendThisMonth + "  " + lastMonthText,
                    color: homeTheme.accent
                )
                Spacer()
                trendFootStat(
                    icon: "chart.line.uptrend.xyaxis",
                    value: PayFormatter.string(averageMonthlyPay, currencyCode: viewModel.settings.currencyCode),
                    color: homeTheme.accent
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var lastMonthText: String {
        guard let last = points.last else { return "" }
        return last.label
    }

    private func trendFootStat(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}