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
        let rate = viewModel.settings.hourlyRate
        let regularPay = breakdown.regularHours * rate
        let ot125Pay = breakdown.ot125Hours * rate * 1.25
        let ot150Pay = breakdown.ot150Hours * rate * 1.5

        return VStack(spacing: 12) {
            sectionTitle(String(localized: "shift.breakdown", defaultValue: "Pay Breakdown"))

            payLine(
                title: String(localized: "summary.regular", defaultValue: "Regular"),
                hours: breakdown.regularHours,
                amount: regularPay
            )
            payLine(
                title: String(localized: "summary.ot125", defaultValue: "125%"),
                hours: breakdown.ot125Hours,
                amount: ot125Pay
            )
            payLine(
                title: String(localized: "summary.ot150", defaultValue: "150%"),
                hours: breakdown.ot150Hours,
                amount: ot150Pay
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
            Text(String(format: "₪%.2f", amount))
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

    init(viewModel: AppViewModel, session: WorkSession) {
        self.viewModel = viewModel
        self.session = session
        _clockIn = State(initialValue: session.clockIn)
        _clockOut = State(initialValue: session.clockOut ?? Date())
        _notes = State(initialValue: session.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.editTimes) {
                    DatePicker(L10n.editClockIn, selection: $clockIn)
                    DatePicker(L10n.editClockOut, selection: $clockOut)
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
                            notes: notes.isEmpty ? nil : notes
                        )
                        dismiss()
                    }
                    .disabled(clockOut <= clockIn)
                }
            }
        }
    }
}
