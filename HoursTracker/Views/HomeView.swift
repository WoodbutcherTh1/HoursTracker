import ActivityKit
import SwiftUI
import UIKit

struct LiveTimerView: View {
    let startDate: Date
    var fontSize: CGFloat = 52
    /// Time to leave out of the count (recorded breaks), so the clock stops while
    /// the worker is on break and resumes where it left off.
    var excludedSeconds: ((Date) -> TimeInterval)?
    /// False while another tab is showing (TabView keeps this view alive off
    /// screen) or a sheet covers Home. Ticking a timer nobody can see is wasted
    /// CPU every second, forever, for as long as a shift stays open — pause it
    /// and freeze on the last real elapsed time instead.
    var isVisible: Bool = true

    var body: some View {
        // `TimelineView` instead of `Timer.publish`/`@State` — the latter froze after
        // the app came back from the background: each time this struct got rebuilt,
        // a brand-new `Timer.publish(...).autoconnect()` instance was created, and the
        // previous one's subscription didn't always reconnect cleanly afterward.
        // `TimelineView` has no subscription to lose; it's driven directly by the
        // system and always reflects the real current date on every redraw.
        //
        // No `onTick` callback out to a parent `@State` anymore (removed 2026-11-09) —
        // that forced the *entire* HomeView body to re-run every second, including
        // three unrelated `OvertimeCalculator.aggregate` calls for the stat cards.
        // Anything that genuinely needs the live date now reads it from its own
        // `TimelineView` scope (see `liveCard`), so only that small subtree re-renders
        // every second instead of the whole screen.
        if isVisible {
            TimelineView(.periodic(from: startDate, by: 1)) { context in
                timerText(at: context.date)
            }
        } else {
            timerText(at: Date())
        }
    }

    private func timerText(at now: Date) -> some View {
        Text(elapsedFormatted(now: now))
            .htFont(size: fontSize, relativeTo: .largeTitle, weight: .light, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            // Without this VoiceOver reads the raw digit string ("zero zero colon
            // one two colon ..."); `.updatesFrequently` tells it this value ticks
            // on its own so it doesn't re-announce every single second a listener
            // happens to be focused here.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.homeTimerElapsedLabel)
            .accessibilityValue(elapsedFormatted(now: now))
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func elapsedFormatted(now: Date) -> String {
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
    @State private var showControlRoomPreview = false
    /// Set once the "Tap to personalize" toast has shown (or the picker was opened).
    @AppStorage("home.themeTipSeen") private var themeTipSeen = false
    @State private var showThemeTip = false
    /// Set once the "Your shift is on the Lock Screen too" toast has shown.
    @AppStorage("home.lockScreenTipSeen") private var lockScreenTipSeen = false
    @State private var showLockScreenTip = false
    /// False while another tab is showing — TabView keeps Home alive off screen.
    @State private var isHomeVisible = true
    /// Bumped on every `onAppear`; the deferred `onDisappear` hide (below) checks
    /// this hasn't moved on before applying, so a quick leave-and-return (faster
    /// than one run-loop tick) can't have its stale hide stomp on the fresh show.
    @State private var homeVisibilityToken = 0

    private var timeFormatter: DateFormatter {
        AppLocale.makeDateFormatter(timeStyle: .short)
    }

    private let calendar = Calendar.current

    private var breaksArePaid: Bool { viewModel.activeSettings.breaksArePaid }

    @State private var naturalContentHeight: CGFloat = 0

    /// How much the GeometryReader is shrunk at the bottom so content clears iOS 26's
    /// floating ("Liquid Glass") tab bar. Clock state needs different amounts:
    /// - **Clocked in**: the tall live-timer layout needs a big reserve so the sparkline
    ///   isn't pushed under the bar.
    /// - **Clocked out**: the short layout is stretched to fill the available height, so
    ///   a big reserve just opens a dead black gap between the graph and the bar; a small
    ///   one lets it drop to a comfortable margin above the bar.
    /// Tunable knobs — nudge per state if the gap/clearance isn't quite right.
    private static let homeBottomReserveClockedIn: CGFloat = 120
    private static let homeBottomReserveClockedOut: CGFloat = 40

    var body: some View {
        NavigationStack {
            ZStack {
                // No ambient decoration: the one glow sits behind the hero (the door
                // when clocked out, the live card when clocked in) and follows the state.
                appBackground.background.ignoresSafeArea()

                // Skip the whole measurement/aggregation subtree while another tab is
                // showing. TabView keeps Home mounted, so without this guard any
                // `viewModel` change anywhere in the app — not just on Home — still
                // re-ran the stat cards' OvertimeCalculator aggregates and the
                // GeometryReader/ViewThatFits layout math to render pixels nobody could
                // see, which is what made switching tabs feel laggy app-wide.
                if isHomeVisible {
                    GeometryReader { geo in
                    // Clamp once at the source: during a tab-switch transition (and
                    // briefly on iOS 26's floating tab bar) this GeometryReader can
                    // report a transient zero or negative size before layout settles.
                    // Every frame calculation below derives from these two values, so
                    // clamping here — instead of at each call site — is what actually
                    // guarantees no `.frame()` downstream ever sees a negative or
                    // non-finite dimension.
                    let availableWidth = max(0, geo.size.width)
                    let availableHeight = max(0, geo.size.height)
                    let metrics = HomeLayoutMetrics(width: availableWidth, height: availableHeight)
                    // ScrollView instead of a hard `.frame(maxHeight: .infinity)`: on
                    // shorter screens, larger Dynamic Type, or a taller system tab bar,
                    // the fixed-height sparkline at the bottom could previously overflow
                    // past the safe area and render underneath the tab bar. `minHeight`
                    // keeps the old vertically-centered look when everything fits, and
                    // lets content scroll instead of getting clipped when it doesn't.
                    let fit = HomeFitScale.factor(available: availableHeight, natural: naturalContentHeight)
                    ZStack {
                        // Hidden measurement probe: always laid out at the real
                        // `availableWidth`, never at `availableWidth / fit`. Measuring
                        // at a fit-dependent width used to feed `naturalContentHeight`
                        // back into the very `fit` value that chose that width — a
                        // closed loop that could oscillate every frame instead of
                        // settling, which is what produced the "NavigationRequestObserver
                        // tried to update multiple times per frame" freeze and invalid
                        // (momentarily negative/non-finite) frame sizes. This probe is
                        // the only thing that writes `naturalContentHeight`, so `fit` is
                        // now a pure function of the previous frame's stable measurement.
                        homeContent(metrics: metrics)
                            .padding(.horizontal, metrics.horizontalPadding)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: HomeNaturalHeightKey.self, value: max(0, proxy.size.height))
                                }
                            )
                            .frame(width: availableWidth)
                            .hidden()
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)

                        // Fits as designed: stretch to the visible height so the Spacers spread the
                        // layout (tall phones). Too tall: scale the whole layout down to fit instead
                        // of pinning controls over the tab bar or cutting them off.
                        ViewThatFits(in: .vertical) {
                            homeContent(metrics: metrics)
                                .padding(.horizontal, metrics.horizontalPadding)
                                .frame(minHeight: availableHeight)

                            ScrollView {
                                homeContent(metrics: metrics)
                                    .padding(.horizontal, metrics.horizontalPadding)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: max(0, availableWidth / fit))
                                    .scaleEffect(fit, anchor: .top)
                                    .frame(
                                        width: availableWidth,
                                        height: max(availableHeight, naturalContentHeight * fit),
                                        alignment: .top
                                    )
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                    }
                    .onPreferenceChange(HomeNaturalHeightKey.self) { naturalContentHeight = $0 }
                    // BUG #3: on shorter screens the door (Clock In / Clock Out) ended up
                    // under the tab bar. There it is pinned above the tab bar and the rest
                    // scrolls behind it, so the main action is always one tap away.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if metrics.pinsDoor {
                            pinnedDoor(metrics: metrics)
                        }
                    }
                }
                // BULLETPROOF floating-tab-bar clearance: physically shrink the
                // GeometryReader by the bar's footprint BEFORE any scaling runs.
                // `.padding` reduces the frame deterministically, so geo.size.height —
                // and therefore `availableHeight` — is already short by
                // `homeBottomReserve`. ViewThatFits/HomeFitScale then fit-or-scroll the
                // content into the region ABOVE the bar in BOTH clock states, and the
                // reserved strip just shows the safe-area-ignoring background (no visible
                // band). Earlier attempts failed because they lived inside the scaled
                // content or used safeAreaInset, which this custom layout fought — a
                // frame-shrinking pad can't be fought.
                .padding(.bottom, viewModel.activeSession != nil
                    ? Self.homeBottomReserveClockedIn
                    : Self.homeBottomReserveClockedOut)
                }
            }
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
                        // (bug / suggestion / …) says what it's about, and the chat with
                        // the developer starts from inside it.
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
            .task(id: viewModel.activeSession?.id) { await runLockScreenTip() }
            .onAppear {
                homeVisibilityToken += 1
                isHomeVisible = true
                // The measurement probe (and the `fit` it drives) only runs while
                // `isHomeVisible` — reset it on return so a tab switch never reuses a
                // stale height measured against a different state (e.g. the active
                // session changed via the widget or Watch while this tab was hidden),
                // which could otherwise scale the layout wrong for the first frame or
                // two after switching back.
                naturalContentHeight = 0
            }
            .onDisappear {
                // Deferred one run-loop tick (plain `.async`, no delay) for the same
                // reason `PayslipsTabView`/`SettingsView` defer their own `onDisappear`
                // navigation-identity resets: flipping `isHomeVisible` here mounts or
                // tears down the GeometryReader/ViewThatFits subtree below, and doing
                // that synchronously lands in the SAME SwiftUI transaction as TabView's
                // own tab-switch update — two structural changes in one transaction is
                // exactly what produces "NavigationRequestObserver tried to update
                // multiple times per frame" and the follow-on freeze/lag switching
                // tabs. `disablesAnimations` on top: without it this can inherit
                // whatever animation is active on the tick it lands on and merge back
                // into the TabView's own transition, the same double-update the
                // dispatch alone is trying to avoid.
                let token = homeVisibilityToken
                DispatchQueue.main.async {
                    // A quick leave-and-return landed an `onAppear` (which bumped the
                    // token) before this tick ran — Home is visible again, so applying
                    // the stale hide here would incorrectly blank the screen the user
                    // is currently looking at.
                    guard token == homeVisibilityToken else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { isHomeVisible = false }
                }
                // "Comes back closed" — same intent as the removed tab-level `.id()`
                // reset in MainTabView, scoped to just this view's own sheets. Plain
                // state, not navigation identity, so these stay synchronous.
                showScanner = false
                showForgotClockIn = false
                showThemePicker = false
                showUserGuide = false
                showAbout = false
                showFeedback = false
                showControlRoomPreview = false
            }
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
            #if DEBUG
            .fullScreenCover(isPresented: $showControlRoomPreview) {
                NavigationStack { AdminControlRoomView() }
            }
            #endif
            .sheet(isPresented: $showFeedback) {
                ContactSupportSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showUserGuide) {
                UserGuideSheet(workerName: viewModel.activeSettings.workerFullName)
                    .presentationDetents([.medium, .large])
            }
            #if DEBUG
            .onAppear {
                // UI-test hook only: open the user guide directly so its pages can be captured.
                if ProcessInfo.processInfo.arguments.contains("UITEST_OPEN_GUIDE") {
                    showUserGuide = true
                }
                if ProcessInfo.processInfo.arguments.contains("UITEST_OPEN_CONTROL_ROOM") {
                    showControlRoomPreview = true
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func homeContent(metrics: HomeLayoutMetrics) -> some View {
        if let session = viewModel.activeSession {
            clockedInView(session: session, metrics: metrics)
        } else {
            clockedOutView(metrics: metrics)
        }
    }

    private func clockedOutView(metrics: HomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.stackSpacing) {
            greetingHeader(metrics: metrics)

            statsRow(metrics: metrics)

            if showsRateCard {
                HomeRateCard(viewModel: viewModel, accent: homeTheme.accent)
            }

            Spacer(minLength: 4)

            // Hero: the door, static, with the single glow behind it (pinned at the
            // bottom instead on shorter screens).
            if !metrics.pinsDoor {
                clockInDoor(metrics: metrics)
                dailyGoalLabel
            }

            if viewModel.shouldOfferForgotClockIn {
                Button {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
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
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                weekdayFullNames: weekDayFullNames,
                highlightedDayIndex: todayWeekdayIndex,
                isTodayShiftOpen: hasOpenShiftToday,
                accent: homeTheme.accent,
                isVisible: isHomeVisible
            )
            // Bottom clearance for the floating tab bar is reserved OUTSIDE this scaled
            // content now — see the `.safeAreaInset(edge: .bottom)` on the outer ZStack
            // in `body`. Putting it here (inside `homeContent`) let HomeFitScale shrink
            // it, so it never actually cleared the iOS 26 floating bar.
        }
    }

    private func greetingHeader(metrics: HomeLayoutMetrics) -> some View {
        HomeGreetingRow(
            name: viewModel.activeSettings.workerFullName,
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
            ringColor: Self.ringColor(for: kind),
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

    /// Each card's own progress-ring color, distinct from the user's personalized
    /// `accent` (which stays on the icon/value) — Month reads Green, Today reads
    /// Cyan, Week reads Purple, so the row is distinguishable at a glance even
    /// when every card shares the same accent.
    private static func ringColor(for kind: HomeStatMetric) -> Color {
        switch kind {
        case .month, .monthPay: return Color(red: 0.173, green: 0.961, blue: 0.596)
        case .today, .todayPay: return Color(red: 0.0, green: 0.898, blue: 1.0)
        case .week, .weekPay: return Color(red: 0.659, green: 0.333, blue: 0.969)
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
                        value: statValue(for: $0),
                        // Today's total only counts completed sessions (`todayHours`);
                        // with a shift actively running and nothing completed yet today,
                        // that reads "00:00" right next to a live-ticking timer — looks
                        // like a bug, not a true zero. Show a spinning hourglass instead
                        // until there's a real number to report.
                        showsHourglass: $0 == .today && todayHours <= 0.01
                    )
                },
                accent: homeTheme.accent,
                compact: metrics.isCompact,
                isVisible: isHomeVisible
            )

            if !metrics.pinsDoor {
                breakControl(session: session, metrics: metrics)
                clockOutDoor(session: session, metrics: metrics)
                dailyGoalLabel
            }

            Spacer(minLength: 4)

            HomeWeekSparkline(
                dailyHours: weekDailyHours,
                weekdayLabels: weekDayLabels,
                highlightedDayIndex: todayWeekdayIndex,
                isTodayShiftOpen: hasOpenShiftToday,
                accent: HomeNeon.coral,
                isVisible: isHomeVisible
            )
            // Bottom clearance reserved outside this scaled content — see the
            // `.safeAreaInset(edge: .bottom)` on the outer ZStack in `body`.
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
        .frame(maxWidth: .infinity)
    }

    /// Today's hours goal under the door — only shown when the user actually set
    /// one (`HomeStatGoals`); same figure the Today stat card's progress ring reads.
    @ViewBuilder
    private var dailyGoalLabel: some View {
        if let goal = statGoal(for: .today) {
            Text(L10n.homeStatsGoal(goal.label))
                .dsFont(.meta, weight: .semibold)
                .foregroundStyle(DS.Palette.textTertiary)
        }
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
        .frame(maxWidth: .infinity)
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
        // Solid behind the pinned controls (content scrolling underneath showed
        // through the break button), with a short fade just above them.
        .background(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [appBackground.background.opacity(0), appBackground.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.pinnedFadeHeight)
                .allowsHitTesting(false)
                appBackground.background
            }
            .padding(.top, -Self.pinnedFadeHeight)
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private static let pinnedFadeHeight: CGFloat = 24

    // MARK: - Clocked-in hero

    /// Coral while working, amber on a break — the status dot, the live card's glow
    /// and the door's Reduce Motion ring all follow it.
    private static func stateColor(for session: WorkSession) -> Color {
        session.isOnBreak ? DS.Palette.onBreak : DS.Palette.clockedIn
    }

    private func statusRow(session: WorkSession, color: Color) -> some View {
        let text = session.activeBreak.map { L10n.homeStatusBreak(timeFormatter.string(from: $0.start)) }
            ?? L10n.homeStatusWorking(timeFormatter.string(from: session.clockIn))
        return VStack(spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.xs) {
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
            // A real row in the stack, not an `.overlay` — an overlay paints on top
            // of whatever is already laid out below it (here, the night/morning/
            // evening shift badge) instead of making room, which is what let this
            // toast's two-line Hebrew text cover the badge. Inserting it in the
            // stack instead pushes the badge down for as long as the toast is
            // showing, so the two can never occupy the same pixels.
            if showLockScreenTip {
                lockScreenTipToast
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            shiftKindLabel(session)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .animation(DS.Motion.state, value: session.isOnBreak)
        .zIndex(1)
    }

    // MARK: - Night shift

    /// The shift's name — morning, evening or night (night per the law: two hours between
    /// 22:00 and 06:00, see `ShiftKind`). Display only: pay uses `WorkSession.isNightShift`,
    /// set at clock-out. A shift that began yesterday says so: it counts on the day it started.
    private func shiftKindLabel(_ session: WorkSession) -> some View {
        // Plain `Date()`, not a ticking source — shift kind (morning/evening/night)
        // and "started yesterday" change at most a few times a day, not every
        // second, so this doesn't need TimelineView; SwiftUI re-renders it
        // naturally whenever something else changes.
        let now = Date()
        let kind = session.shiftKind(now: now, calendar: calendar)
        let startedYesterday = !calendar.isDate(session.clockIn, inSameDayAs: now)
        let name: String
        let icon: String
        let tint: Color
        switch kind {
        case .morning: (name, icon, tint) = (L10n.shiftKindMorning, "sunrise.fill", Self.morningColor)
        case .evening: (name, icon, tint) = (L10n.shiftKindEvening, "sunset.fill", Self.eveningColor)
        case .night: (name, icon, tint) = (L10n.sessionNightShift, "moon.stars.fill", Self.nightColor)
        }
        let text = startedYesterday ? name + " · " + L10n.homeNightStartedYesterday : name
        return HStack(spacing: DS.Space.xxs) {
            Image(systemName: icon)
                .htFont(size: 12, relativeTo: .footnote, weight: .semibold)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.meta, weight: .semibold)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(tint.opacity(0.14)))
        .accessibilityIdentifier("home.shiftKind")
    }

    private static let morningColor = Color(red: 1.0, green: 0.78, blue: 0.35)
    private static let eveningColor = Color(red: 1.0, green: 0.55, blue: 0.40)
    private static let nightColor = Color(red: 0.62, green: 0.64, blue: 1.0)

    // MARK: - "Your shift is on the Lock Screen too" tip

    /// Once, on the first clock-in with Live Activities on: two seconds after the
    /// door opens, for five seconds.
    @MainActor
    private func runLockScreenTip() async {
        guard !lockScreenTipSeen, viewModel.activeSession != nil, !AnnouncementCenter.isAutomatedRun,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            return
        }
        guard viewModel.activeSession != nil, !showThemeTip else { return }
        withAnimation(DS.Motion.state) { showLockScreenTip = true }
        lockScreenTipSeen = true
        try? await Task.sleep(for: .seconds(5))
        withAnimation(DS.Motion.state) { showLockScreenTip = false }
    }

    private var lockScreenTipToast: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "lock.iphone")
                .htFont(size: 14, relativeTo: .footnote, weight: .bold)
                .accessibilityHidden(true)
            Text(L10n.homeTipLockScreen)
                .dsFont(.meta, weight: .semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(DS.Palette.ink)
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .background(Capsule(style: .continuous).fill(homeTheme.accent))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .onTapGesture {
            withAnimation(DS.Motion.state) { showLockScreenTip = false }
        }
        .accessibilityIdentifier("home.lockScreenTip")
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
                isVisible: isHomeVisible
            )
            .environment(\.layoutDirection, .leftToRight)
            .opacity(isPaused ? 0.45 : 1)

            // Scoped to its own TimelineView rather than reading a HomeView-level
            // `@State` updated by LiveTimerView's onTick (removed 2026-11-09) — that
            // forced the entire HomeView body, including three unrelated
            // OvertimeCalculator.aggregate calls for the stat cards, to re-run every
            // second. This way only this small text block re-renders each tick — and
            // only while Home is actually the visible tab; paused otherwise, same as
            // LiveTimerView above.
            if isHomeVisible {
                TimelineView(.periodic(from: session.clockIn, by: 1)) { context in
                    livePayBlock(session: session, now: context.date)
                }
            } else {
                livePayBlock(session: session, now: Date())
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

    private func livePayBlock(session: WorkSession, now: Date) -> some View {
        VStack(spacing: DS.Space.xxs) {
            Text(verbatim: livePayText(for: session, at: now))
                .htFont(size: 28, relativeTo: .title, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
                .foregroundStyle(homeTheme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .accessibilityLabel(L10n.homeLivePay)
                .accessibilityValue(livePayText(for: session, at: now))
            Text(livePayMode == .net ? L10n.sumNoteNet : L10n.sumNoteGross)
                .dsFont(.meta)
                .foregroundStyle(DS.Palette.textTertiary)
        }
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

    /// New users (no finished shift yet) and anyone without a rate see the rate card.
    private var showsRateCard: Bool {
        viewModel.activeSettings.hourlyRate <= 0 || completedSessions.isEmpty
    }

    private var completedSessions: [WorkSession] {
        viewModel.workSessions.filter { $0.clockOut != nil }
    }

    private var todayHours: Double {
        if let stats = viewModel.homeStats { return stats.todayHours }
        // Cold fallback: used only until the first off-main precompute lands.
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
        if let stats = viewModel.homeStats { return stats.weekHours }
        let interval = weekInterval
        return completedSessions
            .filter { interval.contains($0.date) }
            .reduce(0) { $0 + $1.totalHours }
    }

    private var monthShiftCount: Int {
        if let stats = viewModel.homeStats { return stats.monthShiftCount }
        let now = Date()
        return completedSessions.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }.count
    }

    /// Backing breakdowns for the optional "…'s Pay" stat cards — same session
    /// filters as `todayHours`/`weekHours`/`monthShiftCount`, run through the
    /// overtime engine so the figure includes OT tiers, not just base rate × hours.
    private var todayPayBreakdown: DayPayBreakdown {
        if let stats = viewModel.homeStats { return stats.todayPay }
        let today = calendar.startOfDay(for: Date())
        let sessions = completedSessions.filter { calendar.isDate($0.date, inSameDayAs: today) }
        return OvertimeCalculator.aggregate(sessions: sessions, settings: viewModel.activeSettings)
    }

    private var weekPayBreakdown: DayPayBreakdown {
        if let stats = viewModel.homeStats { return stats.weekPay }
        let interval = weekInterval
        let sessions = completedSessions.filter { interval.contains($0.date) }
        return OvertimeCalculator.aggregate(sessions: sessions, settings: viewModel.activeSettings)
    }

    private var monthPayBreakdown: DayPayBreakdown {
        if let stats = viewModel.homeStats { return stats.monthPay }
        let now = Date()
        let sessions = completedSessions.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
        return OvertimeCalculator.aggregate(sessions: sessions, settings: viewModel.activeSettings)
    }

    private var weekDailyHours: [Double] {
        if let stats = viewModel.homeStats { return stats.weekDailyHours }
        return HistoryPeriodHelper.dailyHoursForWeek(
            containing: Date(),
            sessions: viewModel.workSessions,
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

    /// Full weekday names for the sparkline's VoiceOver description — the single
    /// letters in `weekDayLabels` are fine on screen but ambiguous spoken aloud.
    private var weekDayFullNames: [String] {
        let interval = weekInterval
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return "" }
            return HistoryPeriodHelper.weekdayFull(for: day)
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
