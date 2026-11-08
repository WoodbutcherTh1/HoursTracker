import SwiftUI

/// Settings → Work → Work Rules: rest days, holidays, break policy, shift
/// start, currency.
struct WorkRulesView: View {
    @Binding var draft: WorkplaceSettings
    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    var body: some View {
        Form {
            Section {
                restDayPicker
                secondRestDayPicker
                HolidaysSettingsLink(customization: $draft.holidayCustomization)
                breaksArePaidToggle
                // Direct result of the toggle right above it, not an async flag —
                // `Form` only animates insertion in ways that read as a "pop in"
                // when something changes *without* user interaction right here.
                if !draft.breaksArePaid {
                    defaultBreakRow
                }
                shiftStartPicker
                currencyPicker
                aboutRatesDisclosure
            }
        }
        // `Form`/`List` apply an implicit insertion animation while diffing their
        // content on first render — on a pushed screen that reads as rows hidden
        // then popping in. `disablesAnimations` kills that unconditionally so the
        // page renders complete on the very first frame.
        .transaction { $0.disablesAnimations = true }
        .tint(homeTheme.accent)
        .toggleStyle(SwitchToggleStyle(tint: homeTheme.accent))
        .symbolRenderingMode(.monochrome)
        .scrollContentBackground(.hidden)
        .background(appBackground.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 32) }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissible()
        .navigationTitle(L10n.settingsWorkRules)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var restDayPicker: some View {
        Picker(L10n.settingsRestDay, selection: $draft.restDayWeekday) {
            ForEach(1...7, id: \.self) { weekday in
                Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
            }
        }
        .onChange(of: draft.restDayWeekday) { _, newValue in
            if draft.secondRestDayWeekday == newValue {
                draft.secondRestDayWeekday = nil
            }
        }
    }

    private var secondRestDayPicker: some View {
        Picker(
            L10n.settingsSecondRestDay,
            selection: Binding(
                get: { draft.secondRestDayWeekday ?? 0 },
                set: { draft.secondRestDayWeekday = $0 == 0 ? nil : $0 }
            )
        ) {
            Text(L10n.settingsSecondRestDayNone).tag(0)
            ForEach(1...7, id: \.self) { weekday in
                if weekday != draft.restDayWeekday {
                    Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                }
            }
        }
    }

    private var breaksArePaidToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(L10n.settingsBreaksArePaid, isOn: $draft.breaksArePaid)
            Text(draft.breaksArePaid ? L10n.settingsBreaksArePaidOnHint : L10n.settingsBreaksArePaidOffHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var defaultBreakRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.settingsDefaultBreak)
                Spacer()
                breakMinutesStepper
            }
            breakMinutesQuickPicks
        }
        .padding(.vertical, 2)
    }

    private var shiftStartPicker: some View {
        DatePicker(
            L10n.settingsExpectedShiftStart,
            selection: expectedShiftStartBinding,
            displayedComponents: .hourAndMinute
        )
    }

    private var currencyPicker: some View {
        Picker(L10n.settingsCurrency, selection: $draft.currencyCode) {
            ForEach(PayFormatter.supportedCurrencyCodes, id: \.self) { code in
                Text("\(code) (\(PayFormatter.symbol(for: code)))").tag(code)
            }
        }
        .accessibilityIdentifier("settings.currency")
    }

    private var aboutRatesDisclosure: some View {
        DisclosureGroup(L10n.settingsWorkRulesNoteTitle) {
            Text(L10n.settingsWorkRulesNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .font(.caption)
    }

    /// Wraps `expectedShiftStartHour`/`Minute` as a `Date` for the time picker.
    private var expectedShiftStartBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: draft.expectedShiftStartHour,
                    minute: draft.expectedShiftStartMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                draft.expectedShiftStartHour = parts.hour ?? draft.expectedShiftStartHour
                draft.expectedShiftStartMinute = parts.minute ?? draft.expectedShiftStartMinute
            }
        )
    }

    /// Pill-shaped +/- control — a single capsule with the value in the
    /// middle, instead of two separate system stepper buttons.
    private var breakMinutesStepper: some View {
        HStack(spacing: 0) {
            Button {
                draft.defaultBreakMinutes = max(0, draft.defaultBreakMinutes - 5)
            } label: {
                Image(systemName: "minus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .disabled(draft.defaultBreakMinutes <= 0)

            Text("\(draft.defaultBreakMinutes)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 36)

            Button {
                draft.defaultBreakMinutes = min(120, draft.defaultBreakMinutes + 5)
            } label: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .disabled(draft.defaultBreakMinutes >= 120)
        }
        .buttonStyle(.plain)
        .background(Capsule(style: .continuous).fill(Color(.tertiarySystemFill)))
    }

    /// One-tap presets so choosing a common break doesn't mean tapping +/- ten
    /// times — 0/15/30/45 minutes covers the overwhelming majority of shifts.
    private var breakMinutesQuickPicks: some View {
        HStack(spacing: 6) {
            ForEach([0, 15, 30, 45], id: \.self) { minutes in
                Button {
                    draft.defaultBreakMinutes = minutes
                } label: {
                    Text("\(minutes)")
                        .font(.caption.weight(draft.defaultBreakMinutes == minutes ? .bold : .regular).monospacedDigit())
                        .frame(minWidth: 30)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(draft.defaultBreakMinutes == minutes ? Color.appAccent.opacity(0.18) : Color(.tertiarySystemFill))
                        )
                        .foregroundStyle(draft.defaultBreakMinutes == minutes ? Color.appAccent : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
