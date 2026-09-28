import SwiftUI
import UIKit

struct LiveTimerView: View {
    let startDate: Date
    var fontSize: CGFloat = 52
    /// Time to leave out of the count (recorded breaks), so the clock stops while
    /// the worker is on break and resumes where it left off.
    var excludedSeconds: ((Date) -> TimeInterval)?
    var onTick: ((Date) -> Void)?

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(elapsedFormatted)
            .htFont(size: fontSize, relativeTo: .largeTitle, weight: .light, design: .rounded)
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
        let excluded = excludedSeconds?(now) ?? 0
        let elapsed = max(0, Int(now.timeIntervalSince(startDate) - excluded))
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
    @ObservedObject private var notificationPrefs = NotificationPreferences.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @AppStorage("homeStatsReorderHintDismissed") private var didReorderStats = false
    /// Gross/net choice for the live pay counter. Its own key rather than History's
    /// `historyPayDisplayMode`, so switching one screen doesn't silently change the
    /// other. Defaults to gross, which is what this counter showed before it had a
    /// picker at all.
    @AppStorage("homePayDisplayMode") private var livePayMode: PayDisplayMode = .gross
    @State private var showScanner = false
    @State private var showForgotClockIn = false
    @State private var showThemePicker = false
    @State private var showUserGuide = false
    @State private var showAbout = false
    @State private var showFeedback = false
    /// Set once the "Tap to personalize" toast has shown (or the picker was opened).
    @AppStorage("home.themeTipSeen") private var themeTipSeen = false
    @State private var showThemeTip = false
    /// False while another tab is showing — TabView keeps Home alive off screen.
    @State private var isHomeVisible = true
    @State private var liveNow = Date()

    private var timeFormatter: DateFormatter {
        AppLocale.makeDateFormatter(timeStyle: .short)
    }

    private let calendar = Calendar.current

    private var breaksArePaid: Bool { viewModel.settings.breaksArePaid }

    var body: some View {
        NavigationStack {
            ZStack {
                // No ambient decoration: the one glow sits behind the hero (the door
                // when clocked out, the live card when clocked in) and follows the state.
                appBackground.background.ignoresSafeArea()

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
                        .frame(minHeight: geo.size.height - (metrics.pinsDoor ? metrics.pinnedDoorHeight : 0))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // BUG #3: on shorter screens the door (Clock In / Clock Out) ended up
                    // under the tab bar. There it is pinned above the tab bar and the rest
                    // scrolls behind it, so the main action is always one tap away.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if metrics.pinsDoor {
                            pinnedDoor(metrics: metrics)
                        }
                    }
                }
            }
            // Two icons at most. The theme picker lives in the greeting row, the
            // scanner behind the "Import timesheet" button on the screen, and the
            // wordmark in About (the brand mark). SwiftUI mirrors both sides in RTL.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AssistantToolbarButton(onOpen: { viewModel.showAssistant = true })
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showUserGuide = true
                        } label: {
                            Label(L10n.guideTitle, systemImage: "questionmark.circle")
                        }
                        // One row for support and feedback — the sheet's own picker
                        // (bug / suggestion / …) says what it's about.
                        Button {
                            showFeedback = true
                        } label: {
                            Label(L10n.homeHelpFeedback, systemImage: "bubble.left.and.text.bubble.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(homeTheme.accent)
                    }
                    .accessibilityLabel(L10n.homeMore)
                    .accessibilityIdentifier("home.moreMenu")
                }
            }
            .task(id: themeTipDueDate) { await runThemeTip() }
            .onAppear { isHomeVisible = true }
            .onDisappear { isHomeVisible = false }
            .toolbarBackground(appBackground.background, for: .navigationBar)
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
            .onChange(of: showThemePicker) { _, isShowing in
                guard isShowing else { return }
                showThemeTip = false
                themeTipSeen = true
            }
            .sheet(isPresented: $showAbout) {
                AboutSheet(viewModel: viewModel)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showFeedback) {
                ContactSupportSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showUserGuide) {
                UserGuideSheet(workerName: viewModel.settings.workerFullName)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func clockedOutView(metrics: HomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.stackSpacing) {
            greetingHeader(metrics: metrics)

            statsRow(metrics: metrics)

            Spacer(minLength: 4)

            // Hero: the door, static, with the single glow behind it (pinned at the
            // bottom instead on shorter screens).
            if !metrics.pinsDoor {
                clockInDoor(metrics: metrics)
            }

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
        HomeGreetingRow(
            name: viewModel.settings.workerFullName,
            accent: homeTheme.accent,
            compact: metrics.isCompact,
            onBrandTap: { showAbout = true },
            onThemeTap: { showThemePicker = true }
        )
        .padding(.top, DS.Space.xxs)
        // A toast under the row, over the cards — it never pushes the layout.
        .overlay(alignment: .bottomTrailing) {
            if showThemeTip {
                HomeThemeTipToast(accent: homeTheme.accent) { showThemePicker = true }
                    .alignmentGuide(.bottom) { $0[.top] - DS.Space.xxs }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .zIndex(1)
    }

    // MARK: - "Tap to personalize" tip

    /// 60 s after the first Clock Out, once — and only for someone new: the picker
    /// was never used and their first shift is under 30 days old. Long-time users
    /// are not interrupted by a tip for something they have lived without.
    private var themeTipDueDate: Date? {
        guard !themeTipSeen, !HomeAccentTheme.hasSavedChoice, !AnnouncementCenter.isAutomatedRun,
              let firstClockOut = completedSessions.compactMap(\.clockOut).min(),
              Date().timeIntervalSince(firstClockOut) < Self.themeTipNewUserWindow else { return nil }
        return firstClockOut.addingTimeInterval(60)
    }

    private static let themeTipNewUserWindow: TimeInterval = 30 * 24 * 60 * 60

    /// Anything hiding Home — the door stops breathing while it can't be seen.
    ///
    /// Derived, not tracked: every flag here is the `isPresented` source of truth
    /// of a sheet that Home (or the view model) owns, read synchronously in the
    /// same render pass. No notifications or async hops, so a fast open/close can't
    /// leave it stale — the next render always sees the current flags.
    private var isCovered: Bool {
        !isHomeVisible || viewModel.showDaySummary || viewModel.showAssistant || showScanner
            || showForgotClockIn || showThemePicker || showUserGuide || showAbout || showFeedback
    }

    /// Waits for the due time (and for the Day Summary or any picker to close), shows
    /// the toast for 5 s, then marks it seen. Opening the picker ends it early.
    @MainActor
    private func runThemeTip() async {
        guard let due = themeTipDueDate else { return }
        do {
            let wait = due.timeIntervalSinceNow
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            while viewModel.showDaySummary || showThemePicker {
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            return
        }
        withAnimation(DS.Motion.state) { showThemeTip = true }
        try? await Task.sleep(for: .seconds(5))
        withAnimation(DS.Motion.state) { showThemeTip = false }
        themeTipSeen = true
    }

    @ViewBuilder
    private func statsRow(metrics: HomeLayoutMetrics) -> some View {
        if completedSessions.isEmpty {
            HomeStatsWelcomeCard(accent: homeTheme.accent)
        } else {
            VStack(spacing: DS.Space.xs) {
                HStack(spacing: metrics.statsSpacing) {
                    ForEach(homeStatsLayout.order) { kind in
                        reorderableStatCard(kind, metrics: metrics)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                if !didReorderStats {
                    Text(L10n.homeStatsReorderHint)
                        .dsFont(.meta)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
    }

    /// Drag and drop for touch; the long-press menu and VoiceOver actions do the
    /// same one step at a time for anyone who can't drag.
    private func reorderableStatCard(_ kind: HomeStatMetric, metrics: HomeLayoutMetrics) -> some View {
        statCard(for: kind, metrics: metrics)
            .draggable(kind.rawValue) {
                statCard(for: kind, metrics: metrics)
                    .frame(width: 110, height: 96)
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
            .contextMenu {
                if homeStatsLayout.canShift(kind, by: -1) {
                    Button { shiftStat(kind, by: -1) } label: {
                        Label(L10n.homeStatsMoveEarlier, systemImage: "arrow.backward")
                    }
                }
                if homeStatsLayout.canShift(kind, by: 1) {
                    Button { shiftStat(kind, by: 1) } label: {
                        Label(L10n.homeStatsMoveLater, systemImage: "arrow.forward")
                    }
                }
            }
            .accessibilityAction(named: Text(L10n.homeStatsMoveEarlier)) { shiftStat(kind, by: -1) }
            .accessibilityAction(named: Text(L10n.homeStatsMoveLater)) { shiftStat(kind, by: 1) }
    }

    private func shiftStat(_ kind: HomeStatMetric, by offset: Int) {
        guard homeStatsLayout.canShift(kind, by: offset) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        homeStatsLayout.shift(kind, by: offset)
        didReorderStats = true
    }

    /// Display value for a stat, in one place so the full cards (clocked out) and the
    /// compact strip (clocked in) can never show different numbers for the same metric.
    private func statValue(for kind: HomeStatMetric) -> String {
        switch kind {
        case .month: return "\(monthShiftCount)"
        case .week: return HistoryPeriodHelper.formatHoursClock(weekHours)
        case .today: return HistoryPeriodHelper.formatHoursClock(todayHours)
        case .todayPay: return todayPayBreakdown.formattedNetPay
        case .weekPay: return weekPayBreakdown.formattedNetPay
        case .monthPay: return monthPayBreakdown.formattedNetPay
        }
    }

    private func statCard(for kind: HomeStatMetric, metrics: HomeLayoutMetrics) -> some View {
        let goal = statGoal(for: kind)
        return HomeStatCard(
            title: kind.shortTitle,
            accessibilityTitle: kind.title,
            value: statValue(for: kind),
            systemImage: Self.statSymbol(for: kind),
            progress: goal?.progress,
            targetText: goal.map { L10n.homeStatsGoal($0.label) },
            accent: homeTheme.accent,
            compact: metrics.isCompact
        )
    }

    private static func statSymbol(for kind: HomeStatMetric) -> String {
        switch kind {
        case .month, .monthPay: return "calendar"
        case .week, .weekPay: return "chart.bar.fill"
        case .today, .todayPay: return "clock"
        }
    }

    /// Progress against the user's own display-only goal. Pay cards have no target —
    /// a pay goal would be a pay estimate, and those come from the engine only.
    private func statGoal(for kind: HomeStatMetric) -> (progress: Double, label: String)? {
        let goals = HomeStatGoals.current()
        let now = Date()
        switch kind {
        case .today:
            guard let target = goals.todayHoursTarget(on: now, calendar: calendar),
                  let progress = HomeStatGoals.progress(todayHours, target: target) else { return nil }
            return (progress, HistoryPeriodHelper.formatHoursClock(target))
        case .week:
            guard let target = goals.weekHoursTarget,
                  let progress = HomeStatGoals.progress(weekHours, target: target) else { return nil }
            return (progress, HistoryPeriodHelper.formatHoursClock(target))
        case .month:
            guard let target = goals.monthShiftTarget(for: now, calendar: calendar),
                  let progress = HomeStatGoals.progress(Double(monthShiftCount), target: Double(target)) else {
                return nil
            }
            return (progress, "\(target)")
        case .todayPay, .weekPay, .monthPay:
            return nil
        }
    }

    private func clockedInView(session: WorkSession, metrics: HomeLayoutMetrics) -> some View {
        let stateColor = Self.stateColor(for: session)

        return VStack(spacing: metrics.stackSpacing) {
            greetingHeader(metrics: metrics)

            statusRow(session: session, color: stateColor)

            liveCard(session: session, stateColor: stateColor, metrics: metrics)

            HomeCompactStatsStrip(
                items: homeStatsLayout.order.map {
                    HomeCompactStatsStrip.Item(
                        id: $0.rawValue,
                        title: $0.title,
                        value: statValue(for: $0)
                    )
                },
                accent: homeTheme.accent,
                compact: metrics.isCompact
            )

            if !metrics.pinsDoor {
                breakControl(session: session, metrics: metrics)
                clockOutDoor(session: session, metrics: metrics)
            }

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

    // MARK: - Door

    private func clockInDoor(metrics: HomeLayoutMetrics) -> some View {
        HomeAnimatedDoorButton(
            mode: .clockIn,
            title: L10n.homeClockIn,
            compact: metrics.isCompact || metrics.isShort,
            accent: homeTheme.accent
        ) {
            viewModel.clockIn()
        }
        .frame(height: metrics.doorHeight)
        .background(DSHeroGlow(color: homeTheme.accent))
    }

    private func breakControl(session: WorkSession, metrics: HomeLayoutMetrics) -> some View {
        HomeBreakControl(
            session: session,
            targetMinutes: notificationPrefs.breakTargetMinutes,
            isPaid: breaksArePaid,
            accent: homeTheme.accent,
            compact: metrics.isCompact || metrics.isShort,
            onToggle: { viewModel.toggleBreak() }
        )
    }

    private func clockOutDoor(session: WorkSession, metrics: HomeLayoutMetrics) -> some View {
        HomeAnimatedDoorButton(
            mode: .clockOut,
            title: L10n.homeClockOut,
            compact: metrics.isCompact || metrics.isShort,
            accent: homeTheme.accent,
            breathes: true,
            breathingPaused: isCovered,
            stateColor: Self.stateColor(for: session)
        ) {
            viewModel.clockOut()
        }
        .frame(height: metrics.doorHeight)
    }

    /// The door pinned above the tab bar, over a fade so scrolled content slides
    /// under it instead of cutting off at a hard edge. While clocked in the break
    /// button is pinned with it — left in the scroll view it sat half-hidden
    /// behind the door.
    private func pinnedDoor(metrics: HomeLayoutMetrics) -> some View {
        Group {
            if let session = viewModel.activeSession {
                VStack(spacing: metrics.stackSpacing) {
                    breakControl(session: session, metrics: metrics)
                        .padding(.horizontal, metrics.horizontalPadding)
                    clockOutDoor(session: session, metrics: metrics)
                }
            } else {
                clockInDoor(metrics: metrics)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, HomeLayoutMetrics.pinnedDoorTopPadding)
        .background(
            LinearGradient(
                colors: [appBackground.background.opacity(0), appBackground.background],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.35)
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Clocked-in hero

    /// Coral while working, amber on a break — the status dot, the live card's glow
    /// and the door's Reduce Motion ring all follow it.
    private static func stateColor(for session: WorkSession) -> Color {
        session.isOnBreak ? DS.Palette.onBreak : DS.Palette.clockedIn
    }

    private func statusRow(session: WorkSession, color: Color) -> some View {
        let text = session.activeBreak.map { L10n.homeStatusBreak(timeFormatter.string(from: $0.start)) }
            ?? L10n.homeStatusWorking(timeFormatter.string(from: session.clockIn))
        return HStack(spacing: DS.Space.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.headline)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .animation(DS.Motion.state, value: session.isOnBreak)
    }

    /// The live shift's Pay Card: timer, live pay, note and the shared Gross | Net
    /// switch, with the one glow behind it.
    private func liveCard(session: WorkSession, stateColor: Color, metrics: HomeLayoutMetrics) -> some View {
        let isPaused = session.isOnBreak && !breaksArePaid
        return VStack(spacing: DS.Space.sm) {
            // An unpaid break stops the clock; say so in words, not only by dimming.
            Text(L10n.homeTimerPaused)
                .dsFont(.meta, weight: .semibold)
                .foregroundStyle(DS.Palette.onBreak)
                .opacity(isPaused ? 1 : 0)
                .accessibilityHidden(!isPaused)

            LiveTimerView(
                startDate: session.clockIn,
                fontSize: metrics.isCompact ? 42 : 48,
                excludedSeconds: { breaksArePaid ? 0 : session.recordedBreakSeconds(now: $0) },
                onTick: { date in liveNow = date }
            )
            .environment(\.layoutDirection, .leftToRight)
            .opacity(isPaused ? 0.45 : 1)

            VStack(spacing: DS.Space.xxs) {
                Text(verbatim: livePayText(for: session, at: liveNow))
                    .htFont(size: 28, relativeTo: .title, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
                    .foregroundStyle(homeTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .accessibilityLabel(L10n.homeLivePay)
                    .accessibilityValue(livePayText(for: session, at: liveNow))
                Text(livePayMode == .net ? L10n.sumNoteNet : L10n.sumNoteGross)
                    .dsFont(.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            // Widgets, Watch and the Live Activity follow the same choice.
            GrossNetSwitch(mode: $livePayMode, accent: homeTheme.accent) { _ in
                viewModel.refreshLiveSurfaces()
            }
            .frame(maxWidth: 240)
        }
        .padding(.vertical, metrics.isCompact ? DS.Space.md : DS.Space.lg)
        .padding(.horizontal, metrics.isCompact ? DS.Space.md : DS.Space.lg)
        .frame(maxWidth: .infinity)
        .dsCard(radius: DS.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(stateColor.opacity(0.25), lineWidth: 1)
        )
        .background(DSHeroGlow(color: stateColor))
        .animation(DS.Motion.state, value: session.isOnBreak)
    }

    /// The running shift's pay at `now`, read from the view model's live pay curve —
    /// the same curve the Watch, widgets and Live Activity read, so all of them show
    /// the same figure at the same moment. Falls back to pricing the shift directly
    /// if the curve isn't built yet (or belongs to another session).
    private func livePayText(for session: WorkSession, at now: Date) -> String {
        let net = livePayMode == .net
        if let curve = viewModel.liveCurve, curve.sessionID == session.id {
            return PayFormatter.string(curve.pay(at: now, net: net), currencyCode: curve.currencyCode)
        }
        let breakdown = viewModel.liveBreakdown(for: session, at: now, calendar: calendar)
        return net ? breakdown.formattedNetPay : breakdown.formattedGrossPay
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

struct HomeBreakControl: View {
    let session: WorkSession
    let targetMinutes: Int
    /// Paid breaks keep the pay clock running — the card says so, so the worker
    /// knows this break is a reminder only.
    let isPaid: Bool
    let accent: Color
    let compact: Bool
    let onToggle: () -> Void

    var body: some View {
        if let active = session.activeBreak {
            onBreakCard(active)
        } else {
            startButton
        }
    }

    private var startButton: some View {
        Button(action: toggle) {
            Label(L10n.homeBreakStart, systemImage: "cup.and.saucer.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(accent.opacity(0.45), lineWidth: 1)
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func onBreakCard(_ active: BreakInterval) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = active.seconds(now: context.date)
            let target = TimeInterval(max(0, targetMinutes) * 60)
            let remaining = target - elapsed
            let isOver = remaining < 0
            let progress = target > 0 ? min(1, elapsed / target) : 1

            VStack(spacing: compact ? 6 : 8) {
                HStack {
                    Label(L10n.homeOnBreak, systemImage: "cup.and.saucer.fill")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 8)
                    Text(L10n.homeSince(Self.timeFormatter.string(from: active.start)))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text(isOver
                     ? L10n.homeBreakOver(Self.clock(-remaining))
                     : L10n.homeBreakRemaining(Self.clock(remaining)))
                    .font(.system(size: compact ? 22 : 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isOver ? HomeNeon.coral : .white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                ProgressView(value: progress)
                    .tint(isOver ? HomeNeon.coral : accent)
                    .accessibilityHidden(true)

                Text(verbatim: "\(L10n.homeBreakTarget(targetMinutes)) · \(isPaid ? L10n.homeBreakPaid : L10n.homeBreakUnpaid)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))

                Button(action: toggle) {
                    Label(L10n.homeBreakEnd, systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule(style: .continuous).fill(accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(compact ? 12 : 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HomeNeon.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke((isOver ? HomeNeon.coral : accent).opacity(0.4), lineWidth: 1)
                    )
            )
        }
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onToggle()
    }

    private static var timeFormatter: DateFormatter {
        AppLocale.makeDateFormatter(timeStyle: .short)
    }

    /// mm:ss (or h:mm:ss past an hour).
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }
}
