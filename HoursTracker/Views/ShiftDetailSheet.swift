import SwiftUI

struct ShiftDetailSheet: View {
    let session: WorkSession
    let breakdown: DayPayBreakdown
    @ObservedObject var viewModel: AppViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    breakdownCard

                    GrossNetBadge(breakdown: breakdown)

                    if session.isAIImported || session.isManualEntry {
                        Text(entrySourceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "shift.detailTitle", defaultValue: "Shift Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "summary.done", defaultValue: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "edit.title", defaultValue: "Edit")) {
                        showEditor = true
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                EditSessionView(viewModel: viewModel, session: session)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dateFormatter.string(from: session.date))
                .font(.title3.weight(.semibold))
            HStack(spacing: 16) {
                labeledTime(
                    String(localized: "history.col.in", defaultValue: "In"),
                    timeFormatter.string(from: session.clockIn)
                )
                labeledTime(
                    String(localized: "history.col.out", defaultValue: "Out"),
                    session.clockOut.map { timeFormatter.string(from: $0) } ?? "—"
                )
                labeledTime(
                    String(localized: "history.col.hours", defaultValue: "Hours"),
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
            sectionTitle(String(localized: "shift.breakdown", defaultValue: "Pay Breakdown"))

            shiftAttributesLine

            payLine(
                title: tierTitle(base: String(localized: "summary.regular", defaultValue: "Regular"), multiplier: tiers.base),
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
                title: String(localized: "shift.gas", defaultValue: "Travel / Gas"),
                hours: nil,
                amount: breakdown.gasAllowance
            )

            Divider()

            HStack {
                Text(String(localized: "tax.creditPoints", defaultValue: "Credit Points"))
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
            return String(localized: "entry.ai", defaultValue: "Scanned")
        }
        return String(localized: "entry.manual", defaultValue: "Manual")
    }
}

struct EditSessionView: View {
    @ObservedObject var viewModel: AppViewModel
    let session: WorkSession
    @Environment(\.dismiss) private var dismiss

    @State private var clockIn: Date
    @State private var clockOut: Date
    @State private var notes: String
    @State private var breakMinutes: Int
    @State private var dayType: DayType
    @State private var isNightShift: Bool

    init(viewModel: AppViewModel, session: WorkSession) {
        self.viewModel = viewModel
        self.session = session
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
                Section(L10n.editTimes) {
                    DatePicker(L10n.editClockIn, selection: $clockIn)
                    DatePicker(L10n.editClockOut, selection: $clockOut)
                }
                Section(L10n.settingsWorkRules) {
                    Picker(L10n.sessionDayType, selection: $dayType) {
                        ForEach(DayType.allCases) { type in
                            Text(type.localizedName).tag(type)
                        }
                    }
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
                Section(L10n.editNotes) {
                    TextField(L10n.editNotesPlaceholder, text: $notes)
                }
                Section {
                    Button(L10n.editDelete, role: .destructive) {
                        viewModel.deleteSession(session)
                        dismiss()
                    }
                }
            }
            .navigationTitle(L10n.editTitle)
            .navigationBarTitleDisplayMode(.inline)
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
                        dismiss()
                    }
                    .disabled(clockOut <= clockIn)
                }
            }
        }
    }
}
