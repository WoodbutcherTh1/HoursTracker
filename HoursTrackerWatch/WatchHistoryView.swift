import SwiftUI

/// Watch mirror of the phone's History tab: the same payroll-period chrome (prev/
/// next paging, period title + range), a compact calendar of the period's days with
/// each day's pay total, the session list, and the sticky totals + monthly trend.
/// Full-calendar "swipe to expand" and per-row swipe actions (edit/delete/export)
/// don't translate to a watch screen, so every day is shown in a simple scrolling
/// grid instead, and rows are read-only — editing stays on the phone.
struct WatchHistoryView: View {
    @EnvironmentObject private var store: WatchSessionStore
    @State private var selectedDay: Date?

    private var snapshot: WatchSnapshot { store.snapshot }
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                periodHeader

                if !snapshot.historyDays.isEmpty {
                    calendarGrid
                }

                Divider()

                sessionsList

                if !snapshot.historyTrend.isEmpty {
                    trendCard
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .navigationTitle("History")
    }

    private var periodHeader: some View {
        VStack(spacing: 8) {
            HStack {
                periodChevron(systemImage: "chevron.backward") {
                    selectedDay = nil
                    store.shiftHistoryPeriod(by: -1)
                }

                Spacer()

                VStack(spacing: 1) {
                    Text(snapshot.historyPeriodTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(snapshot.historyPeriodRangeLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                periodChevron(systemImage: "chevron.forward") {
                    selectedDay = nil
                    store.shiftHistoryPeriod(by: 1)
                }
            }

            HStack(spacing: 6) {
                totalStat(icon: "clock.fill", label: "Hours", value: formattedHours(snapshot.historyTotalHours), tint: .accentColor)
                totalStat(icon: "banknote.fill", label: "Net pay", value: formattedPay(snapshot.historyTotalNetPay), tint: .green)
                totalStat(icon: "calendar", label: "Days", value: "\(snapshot.historyWorkedDayCount)", tint: .accentColor)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func periodChevron(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func totalStat(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint == .green ? tint : .primary)
            Text(label)
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4) {
            ForEach(snapshot.historyDays) { day in
                dayCell(day)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dayCell(_ day: WatchHistoryDay) -> some View {
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day.date) } == true
        let dayNumber = calendar.component(.day, from: day.date)

        return Button {
            if isSelected {
                selectedDay = nil
            } else {
                selectedDay = day.date
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(dayNumber)")
                    .font(.system(size: 10, weight: day.isToday ? .bold : .regular))
                    .frame(width: 20, height: 20)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if day.isToday {
                            Circle().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
                        }
                    }
                Circle()
                    .fill(day.hasSession && !isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private var sessionsList: some View {
        let sessions = filteredSessions
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    selectedDay == nil ? "All shifts" : "Selected day",
                    systemImage: "list.bullet.rectangle.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                if selectedDay != nil {
                    Spacer()
                    Button("Show all") { selectedDay = nil }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            }

            if sessions.isEmpty {
                Text("No shifts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: WatchHistorySession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(shortDate(session.date))
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(formattedPay(session.netPay))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            HStack {
                Text("\(timeString(session.clockIn)) – \(session.clockOut.map(timeString) ?? "—")")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedHours(session.hours))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("6-MONTH TREND", systemImage: "chart.bar.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            let peak = max(snapshot.historyTrend.map(\.hours).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(snapshot.historyTrend) { point in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(point.hours > 0 ? 0.9 : 0.2))
                            .frame(height: max(3, CGFloat(point.hours / peak) * 34))
                        Text(point.label)
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 46)
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var filteredSessions: [WatchHistorySession] {
        guard let selectedDay else { return snapshot.historySessions }
        return snapshot.historySessions.filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
