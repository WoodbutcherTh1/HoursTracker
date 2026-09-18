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
        VStack(spacing: 4) {
            HStack {
                Button {
                    selectedDay = nil
                    store.shiftHistoryPeriod(by: -1)
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 1) {
                    Text(snapshot.historyPeriodTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(snapshot.historyPeriodRangeLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    selectedDay = nil
                    store.shiftHistoryPeriod(by: 1)
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                VStack(spacing: 1) {
                    Text("Hours")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(formattedHours(snapshot.historyTotalHours))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
                VStack(spacing: 1) {
                    Text("Net pay")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(formattedPay(snapshot.historyTotalNetPay))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
                VStack(spacing: 1) {
                    Text("Days")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text("\(snapshot.historyWorkedDayCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4) {
            ForEach(snapshot.historyDays) { day in
                dayCell(day)
            }
        }
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
                Text(selectedDay == nil ? "All shifts" : "Selected day")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
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
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("6-MONTH TREND")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)

            let peak = max(snapshot.historyTrend.map(\.hours).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(snapshot.historyTrend) { point in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
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
