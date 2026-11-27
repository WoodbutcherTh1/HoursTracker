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
    /// Home shows the card from day one; with no finished shift in the six months
    /// it says where the trend will appear instead of drawing six empty bars.
    var showsEmptyState = false
    @EnvironmentObject private var appLanguage: AppLanguageController
    @ObservedObject private var homeTheme = HomeAccentTheme.shared

    /// Filled by `recomputePoints()` off the main actor — `points` used to be a
    /// computed property re-run (each pass: 6 months × `OvertimeCalculator.aggregate`
    /// over the FULL session history) every time `body` touched it, which `chart`,
    /// `maxHours`, `averageMonthlyPay` and the empty-state check each did
    /// independently — up to 5 full recomputations per render. On a history of a
    /// few years that synchronous multiplication was the actual cost behind
    /// History's multi-second hang on first appearance; this computes once, off
    /// the main thread, and only hops back to assign the finished arrays.
    @State private var points: [MonthlyTrendPoint] = []
    @State private var averageMonthlyPay: Double = 0
    @State private var maxHours: Double = 1

    /// Everything `recomputePoints()` reads — `.task(id:)` only reruns when this
    /// actually changes (all members are `Equatable`), instead of on every publish.
    private struct TrendInputs: Equatable {
        let sessions: [WorkSession]
        let settings: WorkplaceSettings
        let localeID: String
    }

    private var trendInputs: TrendInputs {
        TrendInputs(
            sessions: viewModel.workSessions,
            settings: viewModel.activeSettings,
            localeID: appLanguage.locale.identifier
        )
    }

    private func recomputePoints(_ inputs: TrendInputs) async {
        let computed = await Task.detached(priority: .userInitiated) {
            Self.computeTrend(sessions: inputs.sessions, settings: inputs.settings, localeID: inputs.localeID)
        }.value
        guard !Task.isCancelled else { return }
        points = computed.points
        averageMonthlyPay = computed.averagePay
        maxHours = computed.maxHours
    }

    // `nonisolated` is load-bearing, not decoration: `MonthlyTrendCard` conforms to
    // `View` and carries `@State`/`@ObservedObject`, so Swift infers the WHOLE type
    // — including this `static func` — as `@MainActor` by default. Without
    // `nonisolated`, `Task.detached` below would still have to hop back to the main
    // actor just to call this, silently undoing the entire point of detaching: the
    // "off the main thread" aggregation would actually run back on the main thread.
    private nonisolated static func computeTrend(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        localeID: String
    ) -> (points: [MonthlyTrendPoint], averagePay: Double, maxHours: Double) {
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
            .locale(Locale(identifier: localeID))

        let points: [MonthlyTrendPoint] = months.compactMap { monthStart in
            let interval = calendar.dateInterval(of: .month, for: monthStart)
            let monthSessions = sessions.filter { session in
                guard let interval else { return false }
                return session.clockOut != nil
                    && session.clockIn >= interval.start
                    && session.clockIn < interval.end
            }
            guard !monthSessions.isEmpty else {
                return MonthlyTrendPoint(id: monthStart, label: formatter.format(monthStart), hours: 0, pay: 0)
            }
            let hours = monthSessions.reduce(0) { $0 + $1.effectiveHours }
            let breakdown = OvertimeCalculator.aggregate(sessions: monthSessions, settings: settings)
            return MonthlyTrendPoint(
                id: monthStart,
                label: formatter.format(monthStart),
                hours: hours,
                pay: breakdown.totalPay
            )
        }

        let paid = points.filter { $0.pay > 0 }
        let averagePay = paid.isEmpty ? 0 : paid.reduce(0) { $0 + $1.pay } / Double(paid.count)
        let maxHours = max(points.map(\.hours).max() ?? 0, 1)
        return (points, averagePay, maxHours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .htFont(size: 12, relativeTo: .footnote, weight: .semibold)
                    .foregroundStyle(homeTheme.accent)
                    .accessibilityHidden(true)
                Text(L10n.historyMonthlyTrend.uppercased())
                    .htFont(size: 11, relativeTo: .footnote, weight: .bold, design: .rounded)
                    .foregroundStyle(Color.secondary)
                    .tracking(0.6)
                Spacer()
                Text(L10n.historyTrendHours)
                    .htFont(size: 10, relativeTo: .caption2, weight: .medium, design: .rounded)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .accessibilityElement(children: .combine)

            if showsEmptyState && points.allSatisfy({ $0.hours == 0 }) {
                emptyState
            } else {
                chart
                footer
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
        // The app root applies `.animation(value:)` for toast/undo-banner overlays —
        // that implicit animation reaches this whole subtree, so dismissing a banner
        // elsewhere on screen re-animated this chart's gradient as a visible flash.
        // Cutting the transaction's animation here keeps the chart static unless its
        // own data (`points`) actually changes.
        .transaction { $0.animation = nil }
        .task(id: trendInputs) {
            await recomputePoints(trendInputs)
        }
    }

    private var emptyState: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "chart.bar.xaxis")
                .htFont(size: 20, relativeTo: .title3, weight: .semibold)
                .foregroundStyle(homeTheme.accent.opacity(0.7))
                .accessibilityHidden(true)
            Text(L10n.homeTrendEmpty)
                .dsFont(.sub)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }

    private var chart: some View {
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
            // Swift Charts is silent to VoiceOver by default — a per-mark label +
            // value is what turns each bar into a navigable accessibility element
            // (and unlocks the system's audio-graph gesture). The annotation Text
            // below says the same thing visually, so it's hidden from VoiceOver
            // to avoid announcing each bar's hours twice.
            .accessibilityLabel(point.label)
            .accessibilityValue("\(String(format: "%.0f", point.hours)) \(L10n.manualHours)")
            .annotation(position: .top) {
                if point.hours > 0 {
                    Text(String(format: "%.0f", point.hours))
                        .htFont(size: 9, relativeTo: .caption2, weight: .semibold, design: .rounded)
                        .foregroundStyle(Color.secondary)
                        .monospacedDigit()
                        .accessibilityHidden(true)
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
    }

    private var footer: some View {
        HStack(spacing: 10) {
            trendFootStat(
                icon: "calendar",
                value: L10n.historyTrendThisMonth + "  " + lastMonthText,
                color: homeTheme.accent
            )
            Spacer()
            trendFootStat(
                icon: "chart.line.uptrend.xyaxis",
                value: PayFormatter.string(averageMonthlyPay, currencyCode: viewModel.activeSettings.currencyCode),
                color: homeTheme.accent
            )
        }
    }

    private var lastMonthText: String {
        guard let last = points.last else { return "" }
        return last.label
    }

    private func trendFootStat(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .htFont(size: 10, relativeTo: .caption2, weight: .semibold)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(value)
                .htFont(size: 11, relativeTo: .footnote, weight: .semibold, design: .rounded)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}