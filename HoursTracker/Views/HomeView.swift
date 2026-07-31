import SwiftUI
import UIKit

struct LiveTimerView: View {
    let startDate: Date
    var fontSize: CGFloat = 52
    var onTick: ((Date) -> Void)?

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(elapsedFormatted)
            .font(.system(size: fontSize, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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
    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @ObservedObject private var homeStatsLayout = HomeStatsLayout.shared
    @AppStorage("homeStatsReorderHintDismissed") private var didReorderStats = false
    @State private var showScanner = false
    @State private var showForgotClockIn = false
    @State private var showThemePicker = false
    @State private var showUserGuide = false
    @State private var liveNow = Date()

    private var timeFormatter: DateFormatter {
        AppLocale.makeDateFormatter(timeStyle: .short)
    }

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                HomeNeon.bg.ignoresSafeArea()

                // Ambient neon wash
                Circle()
                    .fill((viewModel.activeSession == nil ? homeTheme.accent : HomeNeon.coral)
                        .opacity(viewModel.activeSession == nil ? 0.12 : 0.08))
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .offset(y: 40)
                    .allowsHitTesting(false)

                HomeAuroraRibbon(accent: viewModel.activeSession == nil ? homeTheme.accent : HomeNeon.coral)
                    .frame(maxHeight: 160)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)

                GeometryReader { geo in
                    let metrics = HomeLayoutMetrics(width: geo.size.width, height: geo.size.height)
                    // ScrollView instead of a hard `.frame(maxHeight: .infinity)`: on
                    // shorter screens, larger Dynamic Type, or a taller system tab bar,
                    // the fixed-height sparkline at the bottom could previously overflow
                    // past the safe area and render underneath the tab bar. `minHeight`
                    // keeps the old vertically-centered look when everything fits, and
                    // lets content scroll instead of getting clipped when it doesn't.
                    ScrollView {
                        Group {
                            if let session = viewModel.activeSession {
                                clockedInView(session: session, metrics: metrics)
                            } else {
                                clockedOutView(metrics: metrics)
                            }
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .frame(minHeight: geo.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HomeBrandTitle(accent: homeTheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showThemePicker = true
                    } label: {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(homeTheme.accent)
                    }
                    .accessibilityLabel(L10n.homeThemeTitle)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "doc.viewfinder")
                            .foregroundStyle(homeTheme.accent)
                    }
                    .accessibilityLabel(L10n.gridTitle)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showUserGuide = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(homeTheme.accent)
                    }
                    .accessibilityLabel(L10n.guideTitle)
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
            .sheet(isPresented: $showForgotClockIn) {
                ForgotClockInSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showThemePicker) {
                HomeThemePickerSheet(theme: homeTheme)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showUserGuide) {
                UserGuideSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func clockedOutView(metrics: HomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.stackSpacing) {
            greetingHeader(metrics: metrics)

            statsRow(metrics: metrics)

            Spacer(minLength: 4)

            HomeAnimatedDoorButton(
                mode: .clockIn,
                title: L10n.homeClockIn,
                compact: metrics.isCompact || metrics.isShort,
                accent: homeTheme.accent
            ) {
                viewModel.clockIn()
            }
            .frame(height: metrics.doorHeight)

            if viewModel.shouldOfferForgotClockIn {
                Button {
                    showForgotClockIn = true
                } label: {
                    Label(L10n.homeForgotClockIn, systemImage: "clock.badge.questionmark")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(HomeNeon.coral)
                        .padding(.horizontal, metrics.isCompact ? 14 : 18)
                        .padding(.vertical, metrics.isCompact ? 8 : 10)
                        .background(
                            Capsule(style: .continuous)
                                .stroke(HomeNeon.coral.opacity(0.55), lineWidth: 1.2)
                                .background(Capsule().fill(HomeNeon.card.opacity(0.7)))
                        )
                }
                .buttonStyle(ScalePressButtonStyle())
                .accessibilityHint(L10n.homeForgotClockInArrivalPrompt)
            }

            Button {
                showScanner = true
            } label: {
                Label(L10n.gridImportButton, systemImage: "doc.viewfinder")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(homeTheme.accent)
                    .padding(.horizontal, metrics.isCompact ? 14 : 18)
                    .padding(.vertical, metrics.isCompact ? 8 : 10)
                    .background(
                        Capsule(style: .continuous)
                            .stroke(homeTheme.accent.opacity(0.55), lineWidth: 1.2)
                            .background(Capsule().fill(HomeNeon.card.opacity(0.7)))
                    )
            }
            .buttonStyle(ScalePressButtonStyle())

            Spacer(minLength: 4)

            HomeWeekSparkline(
                dailyHours: weekDailyHours,
                weekdayLabels: weekDayLabels,
                highlightedDayIndex: todayWeekdayIndex,
                isTodayShiftOpen: hasOpenShiftToday,
                accent: homeTheme.accent
            )
            .padding(.bottom, 2)
        }
    }

    private func greetingHeader(metrics: HomeLayoutMetrics) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let greeting = DaypartGreeting.current(at: context.date, calendar: calendar)
            let title = greeting.title(withName: viewModel.settings.workerFullName)
            ZStack {
                HomeFloatingParticles(accent: homeTheme.accent)
                    .frame(height: metrics.particleHeight)

                Text(title)
                    .font(.system(size: metrics.greetingFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.45)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: title)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
            }
            .padding(.top, 4)
        }
    }

    private func statsRow(metrics: HomeLayoutMetrics) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: metrics.statsSpacing) {
                ForEach(homeStatsLayout.order) { kind in
                    statCard(for: kind, metrics: metrics)
                        .draggable(kind.rawValue) {
                            statCard(for: kind, metrics: metrics)
                                .frame(width: 96)
                                .opacity(0.9)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let dragged = HomeStatMetric(rawValue: raw) else {
                                return false
                            }
                            homeStatsLayout.move(dragged, onto: kind)
                            didReorderStats = true
                            return true
                        }
                }
            }

            if !didReorderStats {
                Text(L10n.homeStatsReorderHint)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private func statCard(for kind: HomeStatMetric, metrics: HomeLayoutMetrics) -> some View {
        switch kind {
        case .month:
            HomeNeonStatCard(
                title: L10n.homeStatMonth,
                value: "\(monthShiftCount)",
                icon: .calendar,
                sparkSeed: 0.4,
                level: Self.normalizedLevel(monthShiftCount, max: Self.monthShiftLevelMax),
                compact: metrics.isCompact,
                showSparkline: metrics.showStatSparkline,
                accent: homeTheme.accent
            )
        case .week:
            HomeNeonStatCard(
                title: L10n.homeStatWeek,
                value: HistoryPeriodHelper.formatHoursClock(weekHours),
                icon: .chart,
                sparkSeed: 1.3,
                level: Self.normalizedLevel(weekHours, max: Self.weekHoursLevelMax),
                compact: metrics.isCompact,
                showSparkline: metrics.showStatSparkline,
                accent: homeTheme.accent
            )
        case .today:
            HomeNeonStatCard(
                title: L10n.homeStatToday,
                value: HistoryPeriodHelper.formatHoursClock(todayHours),
                icon: .clock,
                sparkSeed: 2.2,
                level: Self.normalizedLevel(todayHours, max: Self.todayHoursLevelMax),
                compact: metrics.isCompact,
                showSparkline: metrics.showStatSparkline,
                accent: homeTheme.accent
            )
        case .todayPay:
            HomeNeonStatCard(
                title: L10n.homeStatTodayPay,
                value: todayPayBreakdown.formattedNetPay,
                icon: .clock,
                sparkSeed: 2.7,
                level: Self.normalizedLevel(todayHours, max: Self.todayHoursLevelMax),
                compact: metrics.isCompact,
                showSparkline: metrics.showStatSparkline,
                accent: homeTheme.accent
            )
        case .weekPay:
            HomeNeonStatCard(
                title: L10n.homeStatWeekPay,
                value: weekPayBreakdown.formattedNetPay,
                icon: .chart,
                sparkSeed: 1.7,
                level: Self.normalizedLevel(weekHours, max: Self.weekHoursLevelMax),
                compact: metrics.isCompact,
                showSparkline: metrics.showStatSparkline,
                accent: homeTheme.accent
            )
        case .monthPay:
            HomeNeonStatCard(
                title: L10n.homeStatMonthPay,
                value: monthPayBreakdown.formattedNetPay,
                icon: .calendar,
                sparkSeed: 0.9,
                level: Self.normalizedLevel(monthShiftCount, max: Self.monthShiftLevelMax),
                compact: metrics.isCompact,
                showSparkline: metrics.showStatSparkline,
                accent: homeTheme.accent
            )
        }
    }

    // MARK: - Stat card sparkline levels

    /// Reasonable "full bar" ceilings for each stat, chosen so a typical value sits
    /// mid-height rather than maxing the line out immediately.
    private static let monthShiftLevelMax: Double = 24
    private static let weekHoursLevelMax: Double = 60
    private static let todayHoursLevelMax: Double = 12

    private static func normalizedLevel(_ value: Double, max: Double) -> Double {
        guard max > 0 else { return 0 }
        return Swift.min(Swift.max(value / max, 0), 1)
    }

    private static func normalizedLevel(_ value: Int, max: Double) -> Double {
        normalizedLevel(Double(value), max: max)
    }

    private func clockedInView(session: WorkSession, metrics: HomeLayoutMetrics) -> some View {
        let liveHours = max(0, liveNow.timeIntervalSince(session.clockIn) / 3600)
        let basicGross = liveHours * viewModel.settings.hourlyRate
        let timerSize: CGFloat = metrics.isCompact ? 42 : 52

        return VStack(spacing: metrics.stackSpacing) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let title = DaypartGreeting.current(at: context.date, calendar: calendar)
                    .title(withName: viewModel.settings.workerFullName)
                Text(title)
                    .font(.system(size: metrics.isCompact ? 22 : 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            VStack(spacing: 10) {
                LiveTimerView(startDate: session.clockIn, fontSize: timerSize) { date in
                    liveNow = date
                }

                VStack(spacing: 2) {
                    Text(L10n.homeLiveGrossBasic)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(PayFormatter.string(basicGross, currencyCode: viewModel.settings.currencyCode))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(homeTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, metrics.isCompact ? 14 : 18)
            .padding(.horizontal, metrics.isCompact ? 14 : 20)
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
                title: L10n.homeClockOut,
                compact: metrics.isCompact || metrics.isShort,
                accent: homeTheme.accent
            ) {
                viewModel.clockOut()
            }
            .frame(height: metrics.doorHeight)

            Spacer(minLength: 4)

            HomeWeekSparkline(
                dailyHours: weekDailyHours,
                weekdayLabels: weekDayLabels,
                highlightedDayIndex: todayWeekdayIndex,
                isTodayShiftOpen: hasOpenShiftToday,
                accent: HomeNeon.coral
            )
        }
    }

    // MARK: - Stats

    /// Display-only: open shift for today (sparkline must not show a frozen 00:00).
    private var hasOpenShiftToday: Bool {
        guard let session = viewModel.activeSession else { return false }
        let today = calendar.startOfDay(for: Date())
        return calendar.isDate(session.date, inSameDayAs: today)
            || calendar.isDate(session.clockIn, inSameDayAs: today)
    }

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

    /// Backing breakdowns for the optional "…'s Pay" stat cards — same session
    /// filters as `todayHours`/`weekHours`/`monthShiftCount`, run through the
    /// overtime engine so the figure includes OT tiers, not just base rate × hours.
    private var todayPayBreakdown: DayPayBreakdown {
        let today = calendar.startOfDay(for: Date())
        let sessions = completedSessions.filter { calendar.isDate($0.date, inSameDayAs: today) }
        return OvertimeCalculator.aggregate(sessions: sessions, settings: viewModel.settings)
    }

    private var weekPayBreakdown: DayPayBreakdown {
        let interval = weekInterval
        let sessions = completedSessions.filter { interval.contains($0.date) }
        return OvertimeCalculator.aggregate(sessions: sessions, settings: viewModel.settings)
    }

    private var monthPayBreakdown: DayPayBreakdown {
        let now = Date()
        let sessions = completedSessions.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
        return OvertimeCalculator.aggregate(sessions: sessions, settings: viewModel.settings)
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
                        TaxDeductionsCard(breakdown: breakdown)
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
