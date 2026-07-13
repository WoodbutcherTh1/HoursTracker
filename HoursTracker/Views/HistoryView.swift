import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var editingSession: WorkSession?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sortedSessions.isEmpty {
                    ContentUnavailableView(
                        L10n.historyEmpty,
                        systemImage: "calendar.badge.clock",
                        description: Text(L10n.historyEmptyDescription)
                    )
                } else {
                    List {
                        ForEach(viewModel.sortedSessions) { session in
                            HistoryRow(
                                session: session,
                                breakdown: viewModel.breakdown(for: session),
                                dateFormatter: dateFormatter,
                                timeFormatter: timeFormatter
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingSession = session
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteSession(viewModel.sortedSessions[index])
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(L10n.historyTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ManualEntryView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingSession) { session in
                EditSessionView(viewModel: viewModel, session: session)
            }
        }
    }
}

struct HistoryRow: View {
    let session: WorkSession
    let breakdown: DayPayBreakdown
    let dateFormatter: DateFormatter
    let timeFormatter: DateFormatter

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.isManualEntry ? "pencil.circle.fill" : "bolt.circle.fill")
                .foregroundStyle(session.isManualEntry ? .orange : .blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(dateFormatter.string(from: session.date))
                    .font(.headline)
                Text("\(timeFormatter.string(from: session.clockIn)) – \(session.clockOut.map { timeFormatter.string(from: $0) } ?? "-")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(breakdown.formattedTotalPay)
                    .font(.headline)
                    .monospacedDigit()
                Text(L10n.hoursShort(breakdown.totalHours))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
                        viewModel.updateSession(session, clockIn: clockIn, clockOut: clockOut, notes: notes.isEmpty ? nil : notes)
                        dismiss()
                    }
                    .disabled(clockOut <= clockIn)
                }
            }
        }
    }
}
