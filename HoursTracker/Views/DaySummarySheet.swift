import SwiftUI

/// End-of-shift summary (the reward after Clock Out). One hero amount, the hours
/// as real pay tiers, and every detail one tap away: gross ↔ net, deductions,
/// credit points, this week, edit and delete. Opens at `.medium` showing just the
/// header and the Pay Card; details are at `.large`.
struct DaySummarySheet: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var breakdown: DayPayBreakdown
    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Same key as Home's live counter, so the two always show the same figure.
    @AppStorage("homePayDisplayMode") private var payMode: PayDisplayMode = .gross

    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var deductionsExpanded = false
    @State private var showCreditPointsInfo = false
    @State private var rateText = ""
    @FocusState private var rateFocused: Bool
    @State private var appeared = 0
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var weekRowShown = false
    /// When "This week" was first shown — its sparkle marks it as new for one day.
    @AppStorage("daySummary.weekRowFirstSeen") private var weekRowFirstSeen: Double = 0

    init(viewModel: AppViewModel, breakdown: DayPayBreakdown) {
        self.viewModel = viewModel
        _breakdown = State(initialValue: breakdown)
    }

    private var accent: Color { homeTheme.accent }

    private var completedSession: WorkSession? {
        guard let id = viewModel.lastCompletedSessionID else { return nil }
        return viewModel.sessions.first { $0.id == id }
    }

    var body: some View {
        Group {
            if isEditing, let session = completedSession {
                // The same sheet turns into the editor — nothing stacked on top.
                EditSessionView(
                    viewModel: viewModel,
                    session: session,
                    onDeleted: { viewModel.dismissDaySummary() },
                    onFinish: { setEditing(false) }
                )
                .transition(.opacity)
            } else {
                summary
                    .transition(.opacity)
            }
        }
        // The one haptic of clocking out (the door button stays silent for it).
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear { appeared += 1 }
        .onChange(of: viewModel.sessions) { _, _ in refreshBreakdown() }
    }

    // MARK: - Summary

    private var summary: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    header

                    Group {
                        if viewModel.activeSettings.hourlyRate > 0 {
                            payCard
                        } else {
                            rateMissingCard
                        }
                    }
                    // Behind the card without taking layout space.
                    .background(DSHeroGlow(color: glowColor))

                    if viewModel.activeSettings.hourlyRate > 0 {
                        grossNetSwitch
                        deductionsCard
                    }

                    if let week = weekSummary {
                        weekRow(week)
                            .transition(.opacity)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text(L10n.summaryDeleteThisShift)
                            .dsFont(.sub, weight: .semibold)
                            .foregroundStyle(DS.Palette.clockedIn)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.warning, trigger: showDeleteConfirm) { _, new in new }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.xs)
                .padding(.bottom, DS.Space.xl)
            }
            .accessibilityIdentifier("daySummary.sheet")
            .scrollContentBackground(.hidden)
            .background(appBackground.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        setEditing(true)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(L10n.editTitle)
                    .disabled(completedSession == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.summaryDone) {
                        viewModel.dismissDaySummary()
                    }
                    .accessibilityIdentifier("daySummary.done")
                }
            }
            .toolbarBackground(appBackground.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .overlay(alignment: .bottom) { toastView }
            .alert(L10n.editDeleteConfirm, isPresented: $showDeleteConfirm) {
                Button(L10n.editDelete, role: .destructive) { deleteJustCompletedShift() }
                Button(L10n.editCancel, role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "checkmark.seal.fill")
                .symbolRenderingMode(.hierarchical)
                .htFont(size: 22, relativeTo: .title3, weight: .semibold)
                .foregroundStyle(DS.Palette.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.sumTitle)
                    .dsFont(.titleSection)
                    .foregroundStyle(DS.Palette.textPrimary)
                if let line = shiftLine {
                    Text(verbatim: line)
                        .dsFont(.meta)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Pay Card

    private var payCard: some View {
        let isNet = payMode == .net
        return PayCardView(
            amount: isNet ? breakdown.netPay : breakdown.grossPay,
            currencyCode: breakdown.currencyCode,
            caption: isNet ? AppLocale.tr("pay.net") : AppLocale.tr("pay.gross"),
            note: isNet ? L10n.sumNoteNet : L10n.sumNoteGross,
            tiers: tiers,
            rows: payRows(isNet: isNet),
            accent: accent,
            popsIn: true
        )
        .accessibilityIdentifier("daySummary.payCard")
    }

    /// The shift's tiers at the rate actually paid (rest days / holidays start at 150%).
    private var tiers: [PayTier] {
        PayTier.tiers(for: breakdown, dayType: completedSession?.dayType ?? .regular)
    }

    /// Only rows with something in them. Tier rows carry the tier dot. In net mode each
    /// tier shows its proportional share of the net (display only), so the rows add up
    /// to the net hero.
    private func payRows(isNet: Bool) -> [PayCardView.Row] {
        let dayType = completedSession?.dayType ?? .regular
        var rows: [PayCardView.Row] = tiers.map { tier in
            let time = HistoryPeriodHelper.formatHoursClock(tier.hours)
            let amount = isNet
                ? "≈ " + breakdown.formatted(tier.approximateNet(dayGross: breakdown.grossPay, dayNet: breakdown.netPay))
                : breakdown.formatted(tier.grossPay)
            return .init(
                label: Self.tierLabel(tier, dayType: dayType),
                value: "\(time) · \(amount)",
                dot: PayTier.color(percent: tier.percent, accent: accent)
            )
        }
        if breakdown.gasAllowance > 0.001 {
            let gas = isNet
                ? "≈ " + breakdown.formatted(PayTier.netShare(of: breakdown.gasAllowance, in: breakdown))
                : breakdown.formatted(breakdown.gasAllowance)
            rows.append(.init(label: AppLocale.tr("shift.gas"), value: gas))
        }
        if let minutes = completedSession?.breakMinutes, minutes > 0 {
            let time = HistoryPeriodHelper.formatHoursClock(Double(minutes) / 60)
            let kind = viewModel.activeSettings.breaksArePaid ? L10n.sumBreakPaid : L10n.sumBreakUnpaid
            rows.append(.init(label: L10n.sumRowBreaks, value: "\(time) · \(kind)"))
        }
        return rows
    }

    /// "Regular 100%", "Rest day 150%", "Overtime 175%"…
    static func tierLabel(_ tier: PayTier, dayType: DayType) -> String {
        guard tier.isBase else { return L10n.sumRowOvertime(tier.percent) }
        return dayType == .regular ? L10n.sumRowRegular : "\(dayType.localizedName) \(tier.percent)%"
    }

    /// The glow follows the highest rate worked: orange from 150% (Shabbat, holidays,
    /// long days), gold at 125%, otherwise the accent.
    private var glowColor: Color {
        PayTier.color(percent: PayTier.dominantPercent(tiers) ?? 100, accent: accent)
    }

    // MARK: Rate missing (inline, no second sheet)

    private var rateMissingCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(L10n.sumRateMissing)
                .dsFont(.headline)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.xs) {
                    Text(verbatim: currencySymbol)
                        .dsFont(.numLarge)
                        .foregroundStyle(DS.Palette.textSecondary)
                    // Same as the onboarding rate field: the digits are drawn by
                    // `AmountField` (a plain TextField drew nothing in Hebrew/Arabic).
                    AmountField(
                        text: $rateText,
                        focus: $rateFocused,
                        size: 28,
                        textStyle: .title,
                        weight: .semibold,
                        accent: accent,
                        accessibilityLabel: L10n.onbRateA11y,
                        identifier: "daySummary.rateField"
                    )
                }
                .padding(.horizontal, DS.Space.md)
                .frame(minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Palette.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(rateBorder, lineWidth: rateText.isEmpty ? 1 : 1.5)
                )

                Button(action: saveRate) {
                    Image(systemName: "checkmark")
                        .htFont(size: 17, relativeTo: .body, weight: .bold)
                        .foregroundStyle(DS.Palette.ink)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(accent.opacity(parsedRate == nil ? 0.35 : 1)))
                }
                .buttonStyle(.plain)
                .disabled(parsedRate == nil)
                .accessibilityLabel(L10n.sumRateSave)
            }

            if !rateText.isEmpty, parsedRate == nil {
                Label(L10n.onbRateError, systemImage: "exclamationmark.circle")
                    .dsFont(.meta)
                    .foregroundStyle(DS.Palette.clockedIn)
            }
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(radius: DS.Radius.xl)
    }

    private var parsedRate: Double? { OnboardingEstimate.parseRate(rateText) }

    private var rateBorder: Color {
        if rateText.isEmpty { return DS.Palette.hairline }
        return parsedRate == nil ? DS.Palette.clockedIn : DS.Palette.success
    }

    private func saveRate() {
        guard let rate = parsedRate else { return }
        var settings = viewModel.activeSettings
        settings.hourlyRate = rate
        viewModel.saveActiveWorkplaceSettings(settings)
        refreshBreakdown()
    }

    // MARK: Gross ↔ Net

    private var grossNetSwitch: some View {
        GrossNetSwitch(
            mode: $payMode,
            grossValue: breakdown.formattedGrossPay,
            netValue: breakdown.formattedNetPay,
            accent: accent
        ) { mode in
            viewModel.refreshLiveSurfaces()
            showToast(mode == .net ? L10n.sumHomeSyncNet : L10n.sumHomeSyncGross)
        }
    }

    // MARK: Deductions (collapsed by default, no red)

    private var deductionsCard: some View {
        let total = breakdown.incomeTax + breakdown.nationalInsurance + breakdown.healthTax
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            Button {
                withAnimation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion)) {
                    deductionsExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(verbatim: L10n.sumDeductions(breakdown.formatted(total)))
                        .dsFont(.headline)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .htFont(size: 15, relativeTo: .subheadline, weight: .semibold)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .rotationEffect(.degrees(deductionsExpanded ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(deductionsExpanded ? .isSelected : [])

            if deductionsExpanded {
                VStack(spacing: DS.Space.xs) {
                    deductionRow(AppLocale.tr("tax.incomeTax"), breakdown.incomeTax)
                    deductionRow(AppLocale.tr("tax.nationalInsurance"), breakdown.nationalInsurance)
                    deductionRow(AppLocale.tr("tax.healthTax"), breakdown.healthTax)

                    Rectangle().fill(DS.Palette.hairline).frame(height: 1)

                    HStack(spacing: DS.Space.xs) {
                        Text(AppLocale.tr("tax.creditPoints"))
                            .dsFont(.sub)
                            .foregroundStyle(DS.Palette.textSecondary)
                        Button {
                            withAnimation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion)) {
                                showCreditPointsInfo.toggle()
                            }
                        } label: {
                            Image(systemName: "info.circle")
                                .htFont(size: 15, relativeTo: .subheadline, weight: .regular)
                                .foregroundStyle(DS.Palette.info)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.sumCreditPointsInfo)
                        Spacer()
                        Text(verbatim: breakdown.creditPoints.formatted(.number.precision(.fractionLength(0...2))))
                            .dsFont(.sub, weight: .semibold)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.textPrimary)
                    }
                    if showCreditPointsInfo {
                        Text(L10n.sumCreditPointsInfo)
                            .dsFont(.meta)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(AppLocale.tr("tax.estimateNote"))
                        .dsFont(.meta)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.xs)
        .dsCard()
    }

    /// A normal tax deduction is not an error — "−" with primary text, never red.
    private func deductionRow(_ title: String, _ amount: Double) -> some View {
        HStack {
            Text(title)
                .dsFont(.sub)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            Text(verbatim: "−" + breakdown.formatted(amount))
                .dsFont(.sub, weight: .semibold)
                .monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: This week (from the 3rd shift of the week on)

    private struct WeekSummary {
        let hours: Double
        let pay: String
    }

    private var weekSummary: WeekSummary? {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: completedSession?.date ?? Date()) else {
            return nil
        }
        let week = viewModel.workSessions.filter { $0.clockOut != nil && interval.contains($0.date) }
        guard week.count >= 3 else { return nil }
        let totals = OvertimeCalculator.aggregate(sessions: week, settings: viewModel.activeSettings)
        return WeekSummary(
            hours: totals.totalHours,
            pay: payMode == .net ? totals.formattedNetPay : totals.formattedGrossPay
        )
    }

    private func weekRow(_ week: WeekSummary) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "chart.bar.fill")
                .htFont(size: 17, relativeTo: .body, weight: .semibold)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(verbatim: L10n.sumWeek(HistoryPeriodHelper.formatHoursClock(week.hours), week.pay))
                .dsFont(.sub)
                .foregroundStyle(DS.Palette.textPrimary)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            if weekRowIsNew {
                Image(systemName: "sparkles")
                    .htFont(size: 15, relativeTo: .subheadline, weight: .semibold)
                    .foregroundStyle(accent)
                    .accessibilityLabel(L10n.sumNew)
            }
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Palette.raised)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: week.pay)
        // First appearance: a short fade + 6pt rise (fade only under Reduce Motion).
        .opacity(weekRowShown ? 1 : 0)
        .offset(y: weekRowShown || reduceMotion ? 0 : 6)
        .onAppear {
            if weekRowFirstSeen == 0 { weekRowFirstSeen = Date().timeIntervalSince1970 }
            withAnimation(.easeOut(duration: 0.2)) { weekRowShown = true }
        }
    }

    /// The sparkle shows for one day after "This week" first appears.
    private var weekRowIsNew: Bool {
        weekRowFirstSeen == 0 || Date().timeIntervalSince1970 - weekRowFirstSeen < 24 * 3600
    }

    // MARK: Toast (inside the sheet — the app's own toast sits behind it)

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .dsFont(.sub, weight: .semibold)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
                .background(Capsule(style: .continuous).fill(DS.Palette.raised))
                .overlay(Capsule(style: .continuous).stroke(DS.Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .padding(.bottom, DS.Space.lg)
                .transition(.opacity)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion)) { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion)) { toast = nil }
        }
    }

    // MARK: - Helpers

    private func setEditing(_ editing: Bool) {
        withAnimation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion)) {
            isEditing = editing
        }
    }

    /// "Sun 27 Sep · 08:00 – 16:30" for the shift just closed.
    private var shiftLine: String? {
        guard let session = completedSession, let clockOut = session.clockOut else { return nil }
        let day = AppLocale.makeDateFormatter(template: "EEEdMMM")
        let time = AppLocale.makeDateFormatter(timeStyle: .short)
        return "\(day.string(from: session.clockIn)) · \(time.string(from: session.clockIn)) – \(time.string(from: clockOut))"
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = viewModel.activeSettings.currencyCode
        formatter.locale = AppLocale.resolvedLocale
        return formatter.currencySymbol ?? "₪"
    }

    private func refreshBreakdown() {
        guard let session = completedSession else {
            viewModel.dismissDaySummary()
            return
        }
        breakdown = viewModel.breakdown(for: session)
    }

    private func deleteJustCompletedShift() {
        if let session = completedSession {
            viewModel.deleteSession(session)  // shows its own Undo banner
        }
        viewModel.dismissDaySummary()
    }
}
