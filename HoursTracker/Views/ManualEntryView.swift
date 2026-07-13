import SwiftUI

struct ManualEntryView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate = Date()
    @State private var clockIn = Date()
    @State private var clockOut = Date().addingTimeInterval(8.6 * 3600)
    @State private var useDirectHours = false
    @State private var directHours: Double = 8.6
    @State private var notes = ""

    var body: some View {
        Form {
            Section(L10n.manualDate) {
                DatePicker(L10n.manualWorkDay, selection: $selectedDate, displayedComponents: .date)
            }

            Section(L10n.manualEntryMode) {
                Picker(L10n.manualMode, selection: $useDirectHours) {
                    Text(L10n.manualClockInOut).tag(false)
                    Text(L10n.manualTotalHours).tag(true)
                }
                .pickerStyle(.segmented)
            }

            if useDirectHours {
                Section(L10n.manualHours) {
                    Stepper(value: $directHours, in: 0...24, step: 0.1) {
                        Text(L10n.manualHoursFormat(directHours))
                            .monospacedDigit()
                    }
                }
            } else {
                Section(L10n.editTimes) {
                    DatePicker(L10n.editClockIn, selection: $clockIn, displayedComponents: .hourAndMinute)
                    DatePicker(L10n.editClockOut, selection: $clockOut, displayedComponents: .hourAndMinute)
                }
            }

            Section(L10n.editNotes) {
                TextField(L10n.editNotesPlaceholder, text: $notes)
            }
        }
        .navigationTitle(L10n.manualTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.editSave) {
                    save()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            syncTimesToDate()
        }
        .onChange(of: selectedDate) { _, _ in
            syncTimesToDate()
        }
    }

    private var isValid: Bool {
        if useDirectHours {
            return directHours > 0
        }
        return clockOut > clockIn
    }

    private func syncTimesToDate() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selectedDate)

        var inComponents = calendar.dateComponents([.hour, .minute], from: clockIn)
        inComponents.year = calendar.component(.year, from: day)
        inComponents.month = calendar.component(.month, from: day)
        inComponents.day = calendar.component(.day, from: day)
        if let newIn = calendar.date(from: inComponents) {
            clockIn = newIn
        }

        var outComponents = calendar.dateComponents([.hour, .minute], from: clockOut)
        outComponents.year = calendar.component(.year, from: day)
        outComponents.month = calendar.component(.month, from: day)
        outComponents.day = calendar.component(.day, from: day)
        if let newOut = calendar.date(from: outComponents) {
            clockOut = newOut
        }
    }

    private func save() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selectedDate)

        let finalClockIn: Date
        let finalClockOut: Date

        if useDirectHours {
            finalClockIn = day.addingTimeInterval(8 * 3600)
            finalClockOut = finalClockIn.addingTimeInterval(directHours * 3600)
        } else {
            finalClockIn = clockIn
            finalClockOut = clockOut
        }

        viewModel.addManualSession(
            date: day,
            clockIn: finalClockIn,
            clockOut: finalClockOut,
            notes: notes.isEmpty ? nil : notes
        )
        dismiss()
    }
}
