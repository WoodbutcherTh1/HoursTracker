import SwiftUI
import UIKit

struct LiveTimerView: View {
    let startDate: Date
    var onTick: ((Date) -> Void)?

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(elapsedFormatted)
            .font(.system(size: 52, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .contentTransition(.numericText())
            .onReceive(timer) { date in
                now = date
                onTick?(date)
            }
    }

    private var elapsedFormatted: String {
        let elapsed = max(0, Int(now.timeIntervalSince(startDate)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct HomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showScanner = false
    @State private var liveNow = Date()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private let emerald = Color(red: 0.05, green: 0.62, blue: 0.48)
    private let emeraldDeep = Color(red: 0.02, green: 0.45, blue: 0.38)
    private let coral = Color(red: 0.90, green: 0.32, blue: 0.36)
    private let crimson = Color(red: 0.72, green: 0.16, blue: 0.24)
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                subtleGlow
                HomeAuroraRibbon()
                    .frame(maxHeight: 140)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 4)

                Group {
                    if let session = viewModel.activeSession {
                        clockedInView(session: session)
                    } else {
                        clockedOutView
                    }
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.homeTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "doc.viewfinder")
                    }
                    .accessibilityLabel(String(localized: "scanner.title", defaultValue: "Scan Timesheet"))
                }
            }
            .sheet(isPresented: $viewModel.showDaySummary) {
                if let breakdown = viewModel.lastCompletedBreakdown {
                    DaySummarySheet(breakdown: breakdown) {
                        viewModel.dismissDaySummary()
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showScanner) {
                TimesheetScannerView(appViewModel: viewModel)
            }
        }
    }

    private var subtleGlow: some View {
        Circle()
            .fill((viewModel.activeSession == nil ? emerald : coral).opacity(0.10))
            .frame(width: 260, height: 260)
            .blur(radius: 48)
            .allowsHitTesting(false)
    }

    private var clockedOutView: some View {
        VStack(spacing: 18) {
            greetingHeader

            statsRow

            Spacer(minLength: 8)

            ZStack {
                HomePulseRings(color: emerald)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.clockIn()
                } label: {
                    Text(L10n.homeClockIn)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 18)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [emerald, emeraldDeep],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: emerald.opacity(0.35), radius: 12, y: 6)
                        )
                }
                .buttonStyle(ScalePressButtonStyle())
            }
            .frame(height: 180)

            Button {
                showScanner = true
            } label: {
                Label(
                    String(localized: "scanner.importButton", defaultValue: "Import / Scan Document"),
                    systemImage: "doc.viewfinder"
                )
                .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 8)

            HomeWeekSparkline(
                dailyHours: weekDailyHours,
                weekdayLabels: weekDayLabels,
                accent: emerald
            )
            .padding(.bottom, 4)
        }
    }

    private var greetingHeader: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let greeting = DaypartGreeting.current(at: context.date, calendar: calendar)
            ZStack(alignment: .leading) {
                HomeFloatingParticles()
                    .frame(height: 64)

                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting.title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.35), value: greeting)

                    Text(L10n.homeReadyToStart)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 8)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            HomeStatChip(title: L10n.homeStatMonth, value: "\(monthShiftCount)")
            HomeStatChip(title: L10n.homeStatWeek, value: HistoryPeriodHelper.formatHoursClock(weekHours))
            HomeStatChip(title: L10n.homeStatToday, value: HistoryPeriodHelper.formatHoursClock(todayHours))
        }
    }

    private func clockedInView(session: WorkSession) -> some View {
        let liveHours = max(0, liveNow.timeIntervalSince(session.clockIn) / 3600)
        let basicGross = liveHours * viewModel.settings.hourlyRate

        return VStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(DaypartGreeting.current(at: context.date, calendar: calendar).title)
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 4) {
                Text(L10n.homeClockedIn)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(L10n.homeSince(timeFormatter.string(from: session.clockIn)))
                    .font(.subheadline.weight(.medium))
            }

            VStack(spacing: 10) {
                LiveTimerView(startDate: session.clockIn) { date in
                    liveNow = date
                }

                VStack(spacing: 2) {
                    Text(String(localized: "home.liveGrossBasic", defaultValue: "Estimated gross (hours × rate)"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(PayFormatter.string(basicGross, currencyCode: viewModel.settings.currencyCode))
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            ZStack {
                HomePulseRings(color: coral)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.clockOut()
                } label: {
                    Text(L10n.homeClockOut)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 18)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [coral, crimson],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: coral.opacity(0.35), radius: 12, y: 6)
                        )
                }
                .buttonStyle(ScalePressButtonStyle())
            }
            .frame(height: 180)

            Spacer(minLength: 8)

            HomeWeekSparkline(
                dailyHours: weekDailyHours,
                weekdayLabels: weekDayLabels,
                accent: coral
            )
        }
    }

    // MARK: - Stats

    private var completedSessions: [WorkSession] {
        viewModel.sessions.filter { $0.clockOut != nil }
    }

    private var todayHours: Double {
        let today = calendar.startOfDay(for: Date())
        return completedSessions
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.totalHours }
    }

    private var weekInterval: DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: Date())
            ?? DateInterval(start: Date(), end: Date())
    }

    private var weekHours: Double {
        let interval = weekInterval
        return completedSessions
            .filter { interval.contains($0.date) }
            .reduce(0) { $0 + $1.totalHours }
    }

    private var monthShiftCount: Int {
        let now = Date()
        return completedSessions.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }.count
    }

    private var weekDailyHours: [Double] {
        let interval = weekInterval
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return 0 }
            return completedSessions
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.totalHours }
        }
    }

    private var weekDayLabels: [String] {
        let interval = weekInterval
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return "" }
            return HistoryPeriodHelper.weekdayLetter(for: day)
        }
    }
}

struct ScalePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GrossNetBadge: View {
    let breakdown: DayPayBreakdown

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(String(localized: "pay.gross", defaultValue: "Gross (ברוטו)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(breakdown.formattedGrossPay)
                    .font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 4) {
                Text(String(localized: "pay.net", defaultValue: "Net (נטו)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(breakdown.formattedNetPay)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct DaySummarySheet: View {
    let breakdown: DayPayBreakdown
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)

                    Text(L10n.summaryDayComplete)
                        .font(.title3.weight(.semibold))

                    VStack(spacing: 12) {
                        summaryRow(L10n.summaryRegular, value: L10n.hoursLong(breakdown.regularHours))
                        summaryRow(L10n.summaryOT125, value: L10n.hoursLong(breakdown.ot125Hours))
                        summaryRow(L10n.summaryOT150, value: L10n.hoursLong(breakdown.ot150Hours))
                        summaryRow(
                            String(localized: "shift.gas", defaultValue: "Travel / Gas"),
                            value: breakdown.formatted(breakdown.gasAllowance)
                        )
                        Divider()
                        GrossNetBadge(breakdown: breakdown)
                        summaryRow(
                            String(localized: "tax.creditPoints", defaultValue: "Credit Points"),
                            value: String(format: "%.2f", breakdown.creditPoints)
                        )
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.summaryDone, action: onDismiss)
                }
            }
        }
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
