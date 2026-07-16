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
            .foregroundStyle(.white)
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

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                HomeNeon.bg.ignoresSafeArea()

                // Ambient neon wash
                Circle()
                    .fill(HomeNeon.accent.opacity(viewModel.activeSession == nil ? 0.12 : 0.08))
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .offset(y: 40)
                    .allowsHitTesting(false)

                HomeAuroraRibbon()
                    .frame(maxHeight: 160)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)

                Group {
                    if let session = viewModel.activeSession {
                        clockedInView(session: session)
                    } else {
                        clockedOutView
                    }
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HomeBrandTitle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "doc.viewfinder")
                            .foregroundStyle(HomeNeon.accent)
                    }
                    .accessibilityLabel(L10n.gridTitle)
                }
            }
            .toolbarBackground(HomeNeon.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $viewModel.showDaySummary, onDismiss: {
                viewModel.dismissDaySummary()
            }) {
                if let breakdown = viewModel.lastCompletedBreakdown {
                    DaySummarySheet(viewModel: viewModel, breakdown: breakdown)
                        .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showScanner) {
                BlankTimesheetEntryView(appViewModel: viewModel)
            }
        }
    }

    private var clockedOutView: some View {
        VStack(spacing: 16) {
            greetingHeader

            statsRow

            Spacer(minLength: 6)

            HomeAnimatedDoorButton(
                mode: .clockIn,
                title: L10n.homeClockIn
            ) {
                viewModel.clockIn()
            }
            .frame(height: 140)

            Button {
                showScanner = true
            } label: {
                Label(L10n.gridImportButton, systemImage: "doc.viewfinder")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomeNeon.accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .stroke(HomeNeon.accent.opacity(0.55), lineWidth: 1.2)
                            .background(Capsule().fill(HomeNeon.card.opacity(0.7)))
                    )
            }
            .buttonStyle(ScalePressButtonStyle())

            Spacer(minLength: 6)

            HomeWeekSparkline(
                dailyHours: weekDailyHours,
                weekdayLabels: weekDayLabels,
                highlightedDayIndex: todayWeekdayIndex,
                accent: HomeNeon.accent
            )
            .padding(.bottom, 2)
        }
    }

    private var greetingHeader: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let greeting = DaypartGreeting.current(at: context.date, calendar: calendar)
            let title = greeting.title(withName: viewModel.settings.workerFullName)
            ZStack {
                HomeFloatingParticles()
                    .frame(height: 70)

                Text(title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: title)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            HomeNeonStatCard(
                title: L10n.homeStatMonth,
                value: "\(monthShiftCount)",
                icon: .calendar,
                sparkSeed: 0.4
            )
            HomeNeonStatCard(
                title: L10n.homeStatWeek,
                value: HistoryPeriodHelper.formatHoursClock(weekHours),
                icon: .chart,
                sparkSeed: 1.3
            )
            HomeNeonStatCard(
                title: L10n.homeStatToday,
                value: HistoryPeriodHelper.formatHoursClock(todayHours),
                icon: .clock,
                sparkSeed: 2.2
            )
        }
    }

    private func clockedInView(session: WorkSession) -> some View {
        let liveHours = max(0, liveNow.timeIntervalSince(session.clockIn) / 3600)
        let basicGross = liveHours * viewModel.settings.hourlyRate

        return VStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let title = DaypartGreeting.current(at: context.date, calendar: calendar)
                    .title(withName: viewModel.settings.workerFullName)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: 4) {
                Text(L10n.homeClockedIn)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(L10n.homeSince(timeFormatter.string(from: session.clockIn)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack(spacing: 10) {
                LiveTimerView(startDate: session.clockIn) { date in
                    liveNow = date
                }

                VStack(spacing: 2) {
                    Text(AppLocale.tr("home.liveGrossBasic"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(PayFormatter.string(basicGross, currencyCode: viewModel.settings.currencyCode))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(HomeNeon.accent)
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HomeNeon.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(HomeNeon.coral.opacity(0.25), lineWidth: 1)
                    )
            )

            HomeAnimatedDoorButton(
                mode: .clockOut,
                title: L10n.homeClockOut
            ) {
                viewModel.clockOut()
            }
            .frame(height: 140)

            Spacer(minLength: 6)

            HomeWeekSparkline(
                dailyHours: weekDailyHours,
                weekdayLabels: weekDayLabels,
                highlightedDayIndex: todayWeekdayIndex,
                accent: HomeNeon.coral
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
        HistoryPeriodHelper.dailyHoursForWeek(
            containing: Date(),
            sessions: viewModel.sessions,
            calendar: calendar
        )
    }

    private var weekDayLabels: [String] {
        let interval = weekInterval
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return "" }
            return HistoryPeriodHelper.weekdayLetter(for: day)
        }
    }

    /// Index of today inside the week sparkline row (0...6), if today is in this week.
    private var todayWeekdayIndex: Int? {
        let interval = weekInterval
        let today = calendar.startOfDay(for: Date())
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { continue }
            if calendar.isDate(day, inSameDayAs: today) {
                return offset
            }
        }
        return nil
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
                Text(AppLocale.tr("pay.gross"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(breakdown.formattedGrossPay)
                    .font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 4) {
                Text(AppLocale.tr("pay.net"))
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
    @ObservedObject var viewModel: AppViewModel
    let breakdown: DayPayBreakdown
    @State private var showDeleteConfirm = false

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
                            AppLocale.tr("shift.gas"),
                            value: breakdown.formatted(breakdown.gasAllowance)
                        )
                        Divider()
                        GrossNetBadge(breakdown: breakdown)
                        summaryRow(
                            AppLocale.tr("tax.creditPoints"),
                            value: String(format: "%.2f", breakdown.creditPoints)
                        )
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    Button(L10n.summaryDeleteThisShift, role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                }
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.summaryDone) {
                        viewModel.dismissDaySummary()
                    }
                }
            }
            .alert(
                L10n.editDeleteConfirm,
                isPresented: $showDeleteConfirm
            ) {
                Button(L10n.editDelete, role: .destructive) {
                    deleteJustCompletedShift()
                }
                Button(L10n.editCancel, role: .cancel) {}
            }
        }
    }

    private func deleteJustCompletedShift() {
        if let id = viewModel.lastCompletedSessionID,
           let session = viewModel.sessions.first(where: { $0.id == id }) {
            viewModel.deleteSession(session)
            viewModel.showSuccessToast(L10n.feedbackSessionDeleted)
        }
        viewModel.dismissDaySummary()
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
