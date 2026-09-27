import SwiftUI

/// First-launch onboarding: a one-minute setup that ends with the user's own
/// number ("if you work 8 hours today = ₪X") instead of three slides of text.
///
/// Welcome → hourly rate → week pattern (→ custom days) → expected weekly hours →
/// result. The hourly rate is saved to the workplace settings; the week pattern and
/// weekly hours are DISPLAY ONLY (`DisplayPreferences`) and never reach pay math.
/// Presented once from `MainTabView`'s full-screen cover (`hasSeenOnboarding`).
struct OnboardingView: View {
    @ObservedObject var viewModel: AppViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appLanguage: AppLanguageController
    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    private enum Step: Int {
        case welcome, rate, workType, customDays, weeklyHours, result

        /// Filled segments in the 4-part progress bar.
        var progress: Int {
            switch self {
            case .welcome: return 0
            case .rate: return 1
            case .workType, .customDays: return 2
            case .weeklyHours: return 3
            case .result: return 4
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var movingForward = true
    @State private var rateText = ""
    @State private var pattern: WeekPattern = .fiveDays
    @State private var customDays: Set<Int> = []
    @State private var weeklyHours = 42
    @State private var touchedWeeklyHours = false
    @State private var answeredWeek = false
    @State private var answeredHours = false
    @State private var successTick = 0
    @State private var selectionTick = 0
    @FocusState private var rateFocused: Bool

    // Draft of the flow, so changing the language from the globe — which reloads
    // the whole app, this cover included — returns to the same step with the same
    // answers instead of starting over. Cleared when onboarding finishes.
    @AppStorage("onboarding.lastStep") private var savedStep = -1
    @AppStorage("onboarding.draft.rate") private var savedRate = ""
    @AppStorage("onboarding.draft.pattern") private var savedPattern = ""
    @AppStorage("onboarding.draft.days") private var savedDays = ""
    @AppStorage("onboarding.draft.hours") private var savedHours = 0

    private var accent: Color { homeTheme.accent }
    private var rate: Double? { OnboardingEstimate.parseRate(rateText) }

    /// The settings the preview is priced with: the real settings + the typed rate.
    private var previewSettings: WorkplaceSettings {
        var settings = viewModel.settings
        if let rate { settings.hourlyRate = rate }
        return settings
    }

    var body: some View {
        ZStack(alignment: .top) {
            appBackground.background.ignoresSafeArea()

            DSHeroGlow(color: accent)
                .offset(y: 110)

            VStack(spacing: 0) {
                topBar

                ZStack(alignment: .top) {
                    stepContent
                        .id(step)
                        .transition(stepTransition)
                }
                .padding(.top, DS.Space.xxl)
                .padding(.horizontal, DS.Space.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                bottomActions
            }
        }
        .environment(\.layoutDirection, appLanguage.layoutDirection)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.selection, trigger: selectionTick)
        .onAppear {
            restoreDraft()
            if viewModel.settings.hourlyRate > 0, rateText.isEmpty {
                rateText = Self.plainNumber(viewModel.settings.hourlyRate)
            }
        }
        .onChange(of: step) { _, _ in saveDraft() }
        .onChange(of: rateText) { _, _ in saveDraft() }
        .onChange(of: pattern) { _, _ in saveDraft() }
        .onChange(of: customDays) { _, _ in saveDraft() }
        .onChange(of: weeklyHours) { _, _ in saveDraft() }
    }

    // MARK: - Draft (survives a language change)

    private func saveDraft() {
        savedStep = step.rawValue
        savedRate = rateText
        savedPattern = pattern.rawValue
        savedDays = customDays.sorted().map(String.init).joined(separator: ",")
        savedHours = touchedWeeklyHours || step.rawValue >= Step.weeklyHours.rawValue ? weeklyHours : 0
    }

    private func restoreDraft() {
        guard savedStep >= 0, let restored = Step(rawValue: savedStep) else { return }
        rateText = savedRate
        pattern = WeekPattern(rawValue: savedPattern) ?? .fiveDays
        customDays = Set(savedDays.split(separator: ",").compactMap { Int($0) })
        if savedHours > 0 {
            weeklyHours = savedHours
            touchedWeeklyHours = true
        }
        answeredWeek = restored.rawValue > Step.workType.rawValue
        answeredHours = restored == .result
        movingForward = true
        step = restored
    }

    private func clearDraft() {
        savedStep = -1
        savedRate = ""
        savedPattern = ""
        savedDays = ""
        savedHours = 0
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: DS.Space.sm) {
            Group {
                if step != .welcome {
                    Button(action: goBack) {
                        Image(systemName: "chevron.backward")
                            .dsFont(.headline)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L10n.onbBack)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }

            progressBar

            Menu {
                Picker(L10n.onbLanguage, selection: $appLanguage.preference) {
                    ForEach(AppLanguageOption.allCases) { option in
                        Text(option.pickerLabel).tag(option)
                    }
                }
            } label: {
                Image(systemName: "globe")
                    .htFont(size: 22, relativeTo: .title3, weight: .semibold)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.onbLanguage)

            // Skipping the week and hours steps would leave no preview — the point
            // of onboarding — so "Later" is only offered on the first two.
            if step == .welcome || step == .rate {
                Button(L10n.onbSkip, action: skip)
                    .dsFont(.sub, weight: .semibold)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: 52)
    }

    private var progressBar: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(1...4, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= step.progress ? accent : DS.Palette.hairline)
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion), value: step)
        .accessibilityElement()
        .accessibilityLabel(L10n.onbProgress(max(step.progress, 1), 4))
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .rate: rateStep
        case .workType: workTypeStep
        case .customDays: customDaysStep
        case .weeklyHours: weeklyHoursStep
        case .result: resultStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            ZStack(alignment: .topTrailing) {
                PayCardView(
                    amount: 412.50,
                    currencyCode: viewModel.settings.currencyCode,
                    caption: L10n.onbExampleCaption,
                    title: L10n.onbToday,
                    regularHours: 7,
                    ot125Hours: 2,
                    ot150Hours: 1,
                    accent: accent
                )
                appMark
                    .padding(DS.Space.md)
            }

            Text(L10n.onbWelcomeTitle)
                .dsFont(.titleScreen)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                valueRow(icon: "clock.badge.checkmark", text: L10n.onbWelcomeRow1)
                valueRow(icon: "checkmark.seal", text: L10n.onbWelcomeRow2)
            }
        }
    }

    /// Small brand mark in the hero corner (the full icon is kept for marketing art).
    private var appMark: some View {
        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(accent.opacity(0.15))
            .overlay(
                Image(systemName: "hourglass.bottomhalf.filled")
                    .symbolRenderingMode(.hierarchical)
                    .htFont(size: 15, relativeTo: .subheadline, weight: .semibold)
                    .foregroundStyle(accent)
            )
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    private func valueRow(icon: String, text: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: icon)
                .htFont(size: 22, relativeTo: .title3, weight: .semibold)
                .foregroundStyle(accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rateStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            stepTitle(L10n.onbRateTitle, subtitle: L10n.onbRateSubtitle)

            // Follows the app's direction: [₪][55][✓] in English, ₪ on the right in
            // Hebrew/Arabic. Do NOT force `.leftToRight` on this row or the field:
            // a TextField whose layout direction is flipped against the app's RTL
            // stores the text but doesn't draw it (only the caret shows). The digits
            // still read left to right on their own (bidi), so "557" never reorders.
            HStack(spacing: DS.Space.xs) {
                Text(verbatim: currencySymbol)
                    .dsFont(.numLarge)
                    .foregroundStyle(DS.Palette.textSecondary)
                TextField("0", text: $rateText)
                    .keyboardType(.decimalPad)
                    .focused($rateFocused)
                    // Not `.dsFont(.numHero)`: that also forces `.leftToRight`.
                    .htFont(size: 48, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .tint(accent)
                    .accessibilityLabel(L10n.onbRateA11y)
                    .accessibilityIdentifier("onboarding.rateField")
                // Always in the row (just faded) so the field never resizes and the
                // typed digits never shift when the value turns valid.
                Image(systemName: "checkmark.circle.fill")
                    .htFont(size: 17, relativeTo: .body, weight: .semibold)
                    .foregroundStyle(DS.Palette.success)
                    .opacity(rate != nil ? 1 : 0)
                    .accessibilityHidden(rate == nil)
                    .accessibilityLabel(L10n.onbRateA11y)
                    .accessibilityIdentifier("onboarding.rateValid")
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Palette.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(rateFieldBorder, lineWidth: rateFocused || rateHasError || rate != nil ? 1.5 : 1)
            )
            .shadow(color: rateFocused && !rateHasError ? accent.opacity(0.15) : .clear, radius: 16)
            .animation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion), value: rate != nil)

            if rateHasError {
                Label(L10n.onbRateError, systemImage: "exclamationmark.circle")
                    .dsFont(.meta)
                    .foregroundStyle(DS.Palette.clockedIn)
            }
        }
        .onAppear { rateFocused = true }
    }

    private var rateHasError: Bool { !rateText.isEmpty && rate == nil }

    private var rateFieldBorder: Color {
        if rateHasError { return DS.Palette.clockedIn }
        if rateFocused { return accent }
        if rate != nil { return DS.Palette.success }
        return DS.Palette.hairline
    }

    private var workTypeStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            stepTitle(L10n.onbWeekTitle)
                .padding(.bottom, DS.Space.xs)
            patternCard(.fiveDays, title: L10n.onbWeekFive, subtitle: L10n.onbWeekFiveSub, icon: "calendar")
            patternCard(.sixDays, title: L10n.onbWeekSix, subtitle: L10n.onbWeekSixSub, icon: "calendar")
            patternCard(.varies, title: L10n.onbWeekVaries, subtitle: L10n.onbWeekVariesSub, icon: "calendar.badge.clock")
            patternCard(.custom, title: L10n.onbWeekCustom, subtitle: L10n.onbWeekCustomSub, icon: "square.grid.3x3")
        }
    }

    private func patternCard(_ value: WeekPattern, title: String, subtitle: String, icon: String) -> some View {
        let selected = pattern == value
        return Button {
            pattern = value
            touchedWeeklyHours = false
            selectionTick += 1
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: icon)
                    .htFont(size: 22, relativeTo: .title3, weight: .semibold)
                    .foregroundStyle(accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dsFont(.headline)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(subtitle)
                        .dsFont(.sub)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                Spacer(minLength: DS.Space.xs)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .htFont(size: 22, relativeTo: .title3, weight: .regular)
                    .foregroundStyle(selected ? accent : DS.Palette.textTertiary)
            }
            .padding(DS.Space.md)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(selected ? accent.opacity(0.08) : DS.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(selected ? accent : DS.Palette.hairline, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion), value: selected)
    }

    private var customDaysStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            stepTitle(L10n.onbDaysTitle, subtitle: L10n.onbDaysSubtitle)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.xs), count: 4),
                spacing: DS.Space.xs
            ) {
                ForEach(1...7, id: \.self) { weekday in
                    dayChip(weekday)
                }
            }
        }
    }

    private func dayChip(_ weekday: Int) -> some View {
        let selected = customDays.contains(weekday)
        return Button {
            if selected { customDays.remove(weekday) } else { customDays.insert(weekday) }
            touchedWeeklyHours = false
            selectionTick += 1
        } label: {
            Text(Self.weekdayName(weekday))
                .dsFont(.sub, weight: .semibold)
                .foregroundStyle(selected ? DS.Palette.ink : DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(selected ? accent : DS.Palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(selected ? Color.clear : DS.Palette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var weeklyHoursStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            stepTitle(L10n.onbHoursTitle)

            Text(verbatim: L10n.onbHoursValue(weeklyHours))
                .dsFont(.numHero)
                .foregroundStyle(DS.Palette.textPrimary)
                .contentTransition(.numericText(value: Double(weeklyHours)))
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Slider(
                    value: Binding(
                        get: { Double(weeklyHours) },
                        set: { newValue in
                            let rounded = Int(newValue.rounded())
                            guard rounded != weeklyHours else { return }
                            weeklyHours = rounded
                            touchedWeeklyHours = true
                            selectionTick += 1
                        }
                    ),
                    in: Double(OnboardingEstimate.weeklyHoursRange.lowerBound)...Double(OnboardingEstimate.weeklyHoursRange.upperBound),
                    step: 1
                )
                .tint(accent)
                .accessibilityLabel(L10n.onbHoursTitle)
                .accessibilityValue(L10n.onbHoursValue(weeklyHours))

                Text(L10n.onbHoursNote)
                    .dsFont(.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(verbatim: L10n.onbHoursEstimate(PayFormatter.string(weeklyEstimate, currencyCode: previewSettings.currencyCode)))
                    .dsFont(.numLarge)
                    .foregroundStyle(accent)
                    .contentTransition(.numericText(value: weeklyEstimate))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(L10n.onbEstimateCaption)
                    .dsFont(.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(DS.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
        }
        .animation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion), value: weeklyHours)
        .onAppear {
            if !touchedWeeklyHours {
                weeklyHours = pattern.defaultWeeklyHours(custom: customDays)
            }
        }
    }

    private var weeklyEstimate: Double {
        OnboardingEstimate.weeklyGross(
            settings: previewSettings,
            weeklyHours: weeklyHours,
            workdayCount: pattern.workdays(custom: customDays).count
        )
    }

    private var resultStep: some View {
        let day = OnboardingEstimate.day(settings: previewSettings)
        return VStack(alignment: .leading, spacing: DS.Space.xl) {
            Text(L10n.onbResultTitle)
                .dsFont(.titleSection)
                .foregroundStyle(DS.Palette.textSecondary)

            PayCardView(
                amount: day.grossPay,
                currencyCode: day.currencyCode,
                caption: L10n.onbResultCaption,
                regularHours: day.regularHours,
                ot125Hours: day.ot125Hours,
                ot150Hours: day.ot150Hours,
                rows: [
                    .init(label: L10n.onbResultHours, value: HistoryPeriodHelper.formatHoursClock(day.totalHours)),
                    .init(label: L10n.onbResultPerHour, value: PayFormatter.string(previewSettings.hourlyRate, currencyCode: day.currencyCode))
                ],
                accent: accent
            )

            HStack(spacing: DS.Space.xs) {
                Image(systemName: "lock.shield")
                    .htFont(size: 17, relativeTo: .body, weight: .semibold)
                    .foregroundStyle(DS.Palette.success)
                    .accessibilityHidden(true)
                Text(L10n.onbResultPrivacy)
                    .dsFont(.sub)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .onAppear { successTick += 1 }
    }

    private func stepTitle(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title)
                .dsFont(.titleScreen)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .dsFont(.sub)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: DS.Space.sm) {
            if step == .result {
                // A quiet link, not a second big button: nobody who isn't at work
                // right now should feel pushed to clock in.
                Button {
                    finish(clockIn: true)
                } label: {
                    Label(L10n.onbClockInNow, systemImage: "play.circle")
                        .dsFont(.headline)
                        .foregroundStyle(accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            Button(primaryTitle, action: advance)
                .buttonStyle(DSPrimaryButtonStyle(accent: accent, isEnabled: canAdvance))
                .disabled(!canAdvance)
                .accessibilityIdentifier("onboarding.primary")
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, rateFocused ? DS.Space.sm : DS.Space.xl)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return L10n.onbCtaStart
        case .rate, .workType, .customDays: return L10n.onboardingNext
        case .weeklyHours: return L10n.onbCtaShowResult
        case .result: return L10n.onboardingStart
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .rate: return rate != nil
        case .customDays: return !customDays.isEmpty
        default: return true
        }
    }

    // MARK: - Navigation

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: Edge = movingForward ? .trailing : .leading
        let removal: Edge = movingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    private func go(to next: Step, forward: Bool) {
        if step == .rate { rateFocused = false }
        movingForward = forward
        withAnimation(DS.Motion.animation(DS.Motion.screen, reduceMotion: reduceMotion)) {
            step = next
        }
    }

    private func advance() {
        guard canAdvance else { return }
        switch step {
        case .welcome: go(to: .rate, forward: true)
        case .rate: go(to: .workType, forward: true)
        case .workType:
            answeredWeek = true
            go(to: pattern == .custom ? .customDays : .weeklyHours, forward: true)
        case .customDays: go(to: .weeklyHours, forward: true)
        case .weeklyHours:
            answeredHours = true
            go(to: .result, forward: true)
        case .result: finish(clockIn: false)
        }
    }

    private func goBack() {
        switch step {
        case .welcome: break
        case .rate: go(to: .welcome, forward: false)
        case .workType: go(to: .rate, forward: false)
        case .customDays: go(to: .workType, forward: false)
        case .weeklyHours: go(to: pattern == .custom ? .customDays : .workType, forward: false)
        case .result: go(to: .weeklyHours, forward: false)
        }
    }

    private func skip() {
        saveAnswers()
        clearDraft()
        dismiss()
    }

    private func finish(clockIn: Bool) {
        saveAnswers()
        if clockIn, viewModel.canClockIn {
            viewModel.clockIn()
        }
        clearDraft()
        // Dismissal sets `hasSeenOnboarding` via the cover binding.
        dismiss()
    }

    /// Saves only what the user actually answered: the rate into the workplace
    /// settings (the same path Settings uses), the rest as display-only preferences.
    private func saveAnswers() {
        if let rate, rate != viewModel.settings.hourlyRate {
            var settings = viewModel.settings
            settings.hourlyRate = rate
            viewModel.saveSettings(settings)
        }
        let display = DisplayPreferences.shared
        if answeredWeek {
            display.weekPattern = pattern
            display.customWorkdays = pattern == .custom ? customDays : []
        }
        if answeredHours {
            display.weeklyGoalHoursDisplayOnly = weeklyHours
        }
    }

    // MARK: - Formatting

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = viewModel.settings.currencyCode
        formatter.locale = AppLocale.resolvedLocale
        return formatter.currencySymbol ?? "₪"
    }

    /// "42" / "42.5" — Western digits, no grouping, for pre-filling the rate field.
    private static func plainNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    /// Localized short weekday name (1 = Sunday).
    private static func weekdayName(_ weekday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLocale.resolvedLocale
        let symbols = calendar.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }
}
