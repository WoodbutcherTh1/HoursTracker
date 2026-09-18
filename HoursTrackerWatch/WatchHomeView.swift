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

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if !snapshot.workplaceName.isEmpty {
                    Text(snapshot.workplaceName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(greeting)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if snapshot.isClockedIn, let clockInTime = snapshot.clockInTime {
                    Text(clockInTime, style: .timer)
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .monospacedDigit()
                }

                Button(action: toggleClock) {
                    VStack(spacing: 4) {
                        Image(systemName: snapshot.isClockedIn ? "stop.fill" : "play.fill")
                            .font(.system(size: 22))
                        Text(snapshot.isClockedIn ? "Clock Out" : "Clock In")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(snapshot.isClockedIn ? .red : .green)
                .disabled(isSending)

                statCardsRow

                WatchWeekSparkline(
                    dailyHours: snapshot.weekDailyHours,
                    dayLabels: snapshot.weekDayLabels,
                    todayIndex: snapshot.todayWeekdayIndex
                )
                .padding(.top, 2)

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
                    Button("Refresh") { store.refresh() }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .navigationTitle("HoursTracker")
    }

    private var statCardsRow: some View {
        HStack(spacing: 6) {
            ForEach(orderedMetrics, id: \.self) { metric in
                VStack(spacing: 1) {
                    Text(metric.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(value(for: metric))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
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
        case .todayPay: return "Today's Pay"
        case .weekPay: return "Week's Pay"
        case .monthPay: return "Month's Pay"
        }
    }
}

/// Compact bar-per-day week view — same data as the phone's `HomeWeekSparkline`,
/// drawn as plain bars instead of the neon glow effect (not meaningful at this size).
struct WatchWeekSparkline: View {
    let dailyHours: [Double]
    let dayLabels: [String]
    let todayIndex: Int?

    private var peak: Double { max(dailyHours.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(dailyHours.enumerated()), id: \.offset) { index, hours in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index == todayIndex ? Color.accentColor : Color.white.opacity(0.35))
                        .frame(height: max(3, CGFloat(hours / peak) * 28))
                    Text(dayLabels.indices.contains(index) ? dayLabels[index] : "")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 40)
    }
}
