import SwiftUI

/// Watch mirror of the phone's Home tab: greeting, live timer, Clock In/Out, the
/// same personalized stat-card order, and a compact week sparkline. Simplified for
/// the small screen (no neon backgrounds, no drag-to-reorder — that lives on the
/// phone and this just respects whatever order it chose) but structurally the same
/// screen: same numbers, same order, same actions.
struct WatchHomeView: View {
    @EnvironmentObject private var store: WatchSessionStore
    @State private var isSending = false

    private var snapshot: WatchSnapshot { store.snapshot }
    private var accent: Color { Color(hex: snapshot.accentColorHex) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                clockCard

                statCardsRow

                sparklineCard

                if let error = store.lastErrorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                if snapshot.generatedAt == .distantPast {
                    Text("Open HoursTracker on your iPhone once to sync.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Button {
                        store.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .navigationTitle("HoursTracker")
    }

    private var header: some View {
        VStack(spacing: 2) {
            if !snapshot.workplaceName.isEmpty {
                Text(snapshot.workplaceName.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
                    .tracking(0.6)
                    .lineLimit(1)
            }
            Text(greeting)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    private var clockCard: some View {
        VStack(spacing: 8) {
            if snapshot.isClockedIn, let clockInTime = snapshot.clockInTime {
                Text(clockInTime, style: .timer)
                    .font(.system(size: 32, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            Button(action: toggleClock) {
                HStack(spacing: 6) {
                    Image(systemName: snapshot.isClockedIn ? "stop.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(snapshot.isClockedIn ? "Clock Out" : "Clock In")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(snapshot.isClockedIn ? WatchPalette.coral : accent)
            .disabled(isSending)
        }
        .padding(.vertical, snapshot.isClockedIn ? 10 : 0)
        .background {
            if snapshot.isClockedIn {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(WatchPalette.coral.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(WatchPalette.coral.opacity(0.35), lineWidth: 1)
                    )
            }
        }
    }

    private var statCardsRow: some View {
        HStack(spacing: 6) {
            ForEach(orderedMetrics, id: \.self) { metric in
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.16))
                            .frame(width: 22, height: 22)
                        Image(systemName: metric.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    Text(value(for: metric))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(metric.title)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var sparklineCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THIS WEEK")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            WatchWeekSparkline(
                dailyHours: snapshot.weekDailyHours,
                dayLabels: snapshot.weekDayLabels,
                todayIndex: snapshot.todayWeekdayIndex,
                accent: accent
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var orderedMetrics: [WatchHomeMetric] {
        let ordered = snapshot.homeStatOrder.compactMap(WatchHomeMetric.init(rawValue:))
        return ordered.isEmpty ? [.month, .week, .today] : ordered
    }

    private func value(for metric: WatchHomeMetric) -> String {
        switch metric {
        case .month: return "\(snapshot.monthShiftCount)"
        case .week: return formattedHours(snapshot.weekHours)
        case .today: return formattedHours(snapshot.todayHours)
        case .todayPay: return formattedPay(snapshot.todayNetPay)
        case .weekPay: return formattedPay(snapshot.weekNetPay)
        case .monthPay: return formattedPay(snapshot.monthNetPay)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Working late?"
        }
    }

    private func toggleClock() {
        isSending = true
        if snapshot.isClockedIn {
            store.clockOut()
        } else {
            store.clockIn()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { isSending = false }
    }

    private func formattedHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    private func formattedPay(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = snapshot.currencyCode.isEmpty ? "ILS" : snapshot.currencyCode
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
    }
}

/// Mirrors the phone's `HomeStatMetric` raw values (kept independent since that
/// type lives in an iOS-only file not compiled into the Watch target).
enum WatchHomeMetric: String, CaseIterable {
    case month, week, today, todayPay, weekPay, monthPay

    var title: String {
        switch self {
        case .month: return "Month"
        case .week: return "Week"
        case .today: return "Today"
        case .todayPay: return "Today $"
        case .weekPay: return "Week $"
        case .monthPay: return "Month $"
        }
    }

    var icon: String {
        switch self {
        case .month, .monthPay: return "calendar"
        case .week, .weekPay: return "chart.bar.fill"
        case .today, .todayPay: return "clock.fill"
        }
    }
}

/// Shared fixed semantic colors, matching the phone's `HomeNeon` palette — the
/// "clocked in" coral stays constant everywhere since it carries meaning (an
/// active session), unlike the user-customizable accent color.
enum WatchPalette {
    static let coral = Color(hex: "FF6B5B")
}

/// Compact bar-per-day week view — same data as the phone's `HomeWeekSparkline`,
/// drawn as plain bars instead of the neon glow effect (not meaningful at this size).
struct WatchWeekSparkline: View {
    let dailyHours: [Double]
    let dayLabels: [String]
    let todayIndex: Int?
    let accent: Color

    private var peak: Double { max(dailyHours.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(dailyHours.enumerated()), id: \.offset) { index, hours in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == todayIndex ? accent : Color.white.opacity(0.28))
                        .frame(height: max(3, CGFloat(hours / peak) * 28))
                    Text(dayLabels.indices.contains(index) ? dayLabels[index] : "")
                        .font(.system(size: 8, weight: index == todayIndex ? .bold : .regular))
                        .foregroundStyle(index == todayIndex ? accent : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 40)
    }
}
