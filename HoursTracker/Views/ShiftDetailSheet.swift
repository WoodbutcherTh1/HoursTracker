import SwiftUI

struct ShiftDetailSheet: View {
    let session: WorkSession
    let breakdown: DayPayBreakdown
    @ObservedObject var viewModel: AppViewModel

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @State private var showEditor = false
    @State private var showDeleteConfirm = false

    private var dateFormatter: DateFormatter {
        AppLocale.makeDateFormatter(dateStyle: .full)
    }

    private var timeFormatter: DateFormatter {
        AppLocale.makeDateFormatter(timeStyle: .short)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    breakdownCard

                    GrossNetBadge(breakdown: breakdown)

                    TaxDeductionsCard(breakdown: breakdown)

                    if session.isAIImported || session.isManualEntry {
                        Text(entrySourceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(L10n.summaryDeleteThisShift, role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding()
            }
            .background(appBackground.background.ignoresSafeArea())
            .navigationTitle(AppLocale.tr("shift.detailTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocale.tr("summary.done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(AppLocale.tr("edit.title")) {
                        showEditor = true
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                EditSessionView(viewModel: viewModel, session: session) {
                    dismiss()
                }
            }
            .alert(L10n.editDeleteConfirm, isPresented: $showDeleteConfirm) {
                Button(L10n.editDelete, role: .destructive) {
                    viewModel.deleteSession(session)
                    viewModel.showSuccessToast(L10n.feedbackSessionDeleted)
                    dismiss()
                }
                Button(L10n.editCancel, role: .cancel) {}
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dateFormatter.string(from: session.date))
                .font(.title3.weight(.semibold))
            HStack(spacing: 16) {
                labeledTime(
                    AppLocale.tr("history.col.in"),
                    timeFormatter.string(from: session.clockIn)
                )
                labeledTime(
                    AppLocale.tr("history.col.out"),
                    session.clockOut.map { timeFormatter.string(from: $0) } ?? "—"
                )
                labeledTime(
                    AppLocale.tr("history.col.hours"),
                    HistoryPeriodHelper.formatHoursClock(breakdown.totalHours)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func labeledTime(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private var breakdownCard: some View {
        let tiers = OvertimeCalculator.tiers(for: session.dayType)

        return VStack(spacing: 12) {
            sectionTitle(AppLocale.tr("shift.breakdown"))

            shiftAttributesLine

            payLine(
                title: tierTitle(base: AppLocale.tr("summary.regular"), multiplier: tiers.base),
                hours: breakdown.regularHours,
                amount: breakdown.basePay
            )
            payLine(
                title: percentTitle(tiers.tier1),
                hours: breakdown.ot125Hours,
                amount: breakdown.ot125Pay
            )
            payLine(
                title: percentTitle(tiers.tier2),
                hours: breakdown.ot150Hours,
                amount: breakdown.ot150Pay
            )
            payLine(
                title: AppLocale.tr("shift.gas"),
                hours: nil,
                amount: breakdown.gasAllowance
            )

            Divider()

            HStack {
                Text(AppLocale.tr("tax.creditPoints"))
                Spacer()
                Text(String(format: "%.2f", breakdown.creditPoints))
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Day type, night shift, and break — the inputs that shaped the rates below.
    private var shiftAttributesLine: some View {
        HStack(spacing: 6) {
            attributeBadge(session.dayType.localizedName, highlighted: session.dayType.isPremium)
            if session.isNightShift {
                attributeBadge(L10n.sessionNightShift, highlighted: true)
            }
            if session.breakMinutes > 0 {
                attributeBadge("\(L10n.sessionBreakMinutes): \(session.breakMinutes)", highlighted: false)
            }
            Spacer()
        }
    }

    private func attributeBadge(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(highlighted ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill)))
            .foregroundStyle(highlighted ? Color.accentColor : Color.secondary)
    }

    private func tierTitle(base: String, multiplier: Double) -> String {
        multiplier == 1.0 ? base : percentTitle(multiplier)
    }

    private func percentTitle(_ multiplier: Double) -> String {
        "\(Int((multiplier * 100).rounded()))%"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func payLine(title: String, hours: Double?, amount: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let hours {
                    Text(HistoryPeriodHelper.formatHoursClock(hours))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(breakdown.formatted(amount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private var entrySourceLabel: String {
        if session.isAIImported {
            return AppLocale.tr("entry.ai")
        }
        return AppLocale.tr("entry.manual")
    }
}

struct EditSessionView: View {
    @ObservedObject var viewModel: AppViewModel
    let session: WorkSession
    /// Called after a successful delete so parent sheets (e.g. Shift Details) can close too.
    var onDeleted: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var clockIn: Date
    @State private var clockOut: Date
    @State private var notes: String
    @State private var breakMinutes: Int
    @State private var dayType: DayType
    @State private var isNightShift: Bool
    @State private var showDeleteConfirm = false

    init(
        viewModel: AppViewModel,
        session: WorkSession,
        onDeleted: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.session = session
        self.onDeleted = onDeleted
        _clockIn = State(initialValue: session.clockIn)
        _clockOut = State(initialValue: session.clockOut ?? Date())
        _notes = State(initialValue: session.notes ?? "")
        _breakMinutes = State(initialValue: session.breakMinutes)
        _dayType = State(initialValue: session.dayType)
        _isNightShift = State(initialValue: session.isNightShift)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.settingsWorkRules) {
                    Picker(L10n.sessionDayType, selection: $dayType) {
                        ForEach(DayType.allCases) { type in
                            Text(type.localizedName).tag(type)
                        }
                    }
                }
                if dayType == .holiday {
                    Section(L10n.manualHolidayAutoFilledTitle) {
                        LabeledContent(L10n.editClockIn, value: clockIn.formatted(date: .omitted, time: .shortened))
                        LabeledContent(L10n.editClockOut, value: clockOut.formatted(date: .omitted, time: .shortened))
                        Text(L10n.manualHolidayAutoFilledHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if dayType == .sick {
                    Section(L10n.dayTypeSick) {
                        let preview = viewModel.sickStreakPreview(for: session.date)
                        Text(L10n.manualSickPreview(preview.dayNumber, Int(preview.percentage * 100)))
                            .font(.subheadline.weight(.semibold))
                        Text(L10n.manualSickHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section(L10n.editTimes) {
                        DatePicker(L10n.editClockIn, selection: $clockIn)
                        DatePicker(L10n.editClockOut, selection: $clockOut)
                    }
                }
                if dayType != .sick {
                    Section {
                        Toggle(L10n.sessionNightShift, isOn: $isNightShift)
                        Stepper(value: $breakMinutes, in: 0...240, step: 5) {
                            HStack {
                                Text(L10n.sessionBreakMinutes)
                                Spacer()
                                Text("\(breakMinutes)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section(L10n.editNotes) {
                    TextField(L10n.editNotesPlaceholder, text: $notes)
                }
                Section {
                    Button(L10n.editDelete, role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(L10n.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissible()
            .onChange(of: dayType) { _, newValue in
                if newValue == .holiday {
                    let expected = viewModel.settings.expectedShift(on: session.date)
                    clockIn = expected.clockIn
                    clockOut = expected.clockOut
                } else if newValue == .sick {
                    let day = Calendar.current.startOfDay(for: session.date)
                    clockIn = day
                    clockOut = day
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.editCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.editSave) {
                        viewModel.updateSession(
                            session,
                            clockIn: clockIn,
                            clockOut: clockOut,
                            notes: notes.isEmpty ? nil : notes,
                            breakMinutes: breakMinutes,
                            dayType: dayType,
                            isNightShift: isNightShift
                        )
                        viewModel.showSuccessToast(L10n.feedbackSessionUpdated)
                        dismiss()
                    }
                    .disabled(dayType != .sick && sameClockTimes)
                }
            }
            .alert(
                L10n.editDeleteConfirm,
                isPresented: $showDeleteConfirm
            ) {
                Button(L10n.editDelete, role: .destructive) {
                    viewModel.deleteSession(session)
                    viewModel.showSuccessToast(L10n.feedbackSessionDeleted)
                    if let onDeleted {
                        onDeleted()
                    } else {
                        dismiss()
                    }
                }
                Button(L10n.editCancel, role: .cancel) {}
            }
        }
    }

    private var sameClockTimes: Bool {
        let calendar = Calendar.current
        let inParts = calendar.dateComponents([.hour, .minute], from: clockIn)
        let outParts = calendar.dateComponents([.hour, .minute], from: clockOut)
        return inParts.hour == outParts.hour && inParts.minute == outParts.minute
    }
}
