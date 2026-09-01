import SwiftUI

struct ManualEntryView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showSickCapAlert = false
    @State private var selectedDate = Date()
    @State private var clockIn = Date()
    @State private var clockOut = Date().addingTimeInterval(8.6 * 3600)
    @State private var useDirectHours = false
    @State private var directHours: Double = 8.6
    @State private var notes = ""
    @State private var breakMinutes = 0
    @State private var dayType: DayType = .regular
    @State private var isNightShift = false

    var body: some View {
        Form {
            Section(L10n.manualDate) {
                DatePicker(L10n.manualWorkDay, selection: $selectedDate, displayedComponents: .date)
            }

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
                    let preview = viewModel.sickStreakPreview(for: selectedDate)
                    Text(L10n.manualSickPreview(preview.dayNumber, Int(preview.percentage * 100)))
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.manualSickHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
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

            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                }
            }

            Section(L10n.editNotes) {
                TextField(L10n.editNotesPlaceholder, text: $notes)
            }
        }
        .navigationTitle(L10n.manualTitle)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible()
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
            breakMinutes = viewModel.settings.defaultBreakMinutes
            dayType = viewModel.resolvedDayType(for: selectedDate)
            applyHolidayAutoFillIfNeeded()
        }
        .onChange(of: selectedDate) { _, _ in
            syncTimesToDate()
            dayType = viewModel.resolvedDayType(for: selectedDate)
            applyHolidayAutoFillIfNeeded()
        }
        .onChange(of: dayType) { _, _ in
            applyHolidayAutoFillIfNeeded()
        }
        .alert(L10n.errorTitle, isPresented: $showSickCapAlert) {
            Button(L10n.errorOK, role: .cancel) {}
        } message: {
            Text(L10n.sickDayCapReached)
        }
    }

    /// Holiday hours are never typed in — they're derived from the worker's
    /// typical shift, since a holiday isn't a day anyone actually clocked.
    private func applyHolidayAutoFillIfNeeded() {
        guard dayType == .holiday else { return }
        let expected = viewModel.settings.expectedShift(on: selectedDate)
        clockIn = expected.clockIn
        clockOut = expected.clockOut
        useDirectHours = false
    }

    /// Shift length in minutes as entered, before any break deduction.
    /// Returns nil when the times are invalid (equal clock in/out).
    private var enteredShiftMinutes: Int? {
        if dayType == .holiday || dayType == .sick { return nil }
        if useDirectHours {
            return Int(directHours * 60)
        }
        let calendar = Calendar.current
        let inParts = calendar.dateComponents([.hour, .minute], from: clockIn)
        let outParts = calendar.dateComponents([.hour, .minute], from: clockOut)
        if inParts.hour == outParts.hour && inParts.minute == outParts.minute {
            return nil // zero-duration (identical wall-clock times)
        }
        var minutes = outParts.hour! * 60 + outParts.minute!
            - (inParts.hour! * 60 + inParts.minute!)
        if minutes <= 0 {
            minutes += 24 * 60 // overnight shift
        }
        return minutes
    }

    /// Inline validation message shown above the save button; nil when valid.
    private var validationMessage: String? {
        guard dayType != .holiday, dayType != .sick else { return nil }

        // Zero-duration shift (0 hours, or identical clock-in/out times).
        guard let shiftMinutes = enteredShiftMinutes, shiftMinutes > 0 else {
            return L10n.manualErrorZeroDuration
        }

        // A break that eats the whole shift leaves zero paid time. Negative
        // breaks are impossible via the stepper but guarded anyway.
        guard breakMinutes >= 0, breakMinutes < shiftMinutes else {
            return L10n.manualErrorBreakExceedsShift
        }
        return nil
    }

    private var isValid: Bool {
        validationMessage == nil
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

        if dayType == .sick {
            let added = viewModel.addSickDay(date: day, notes: notes.isEmpty ? nil : notes)
            if added {
                viewModel.showSuccessToast(L10n.feedbackSessionSaved)
            } else {
                // Annual cap reached — `errorMessage` was set, but this sheet can
                // be presented from a tab whose alert isn't visible, so surface
                // the message right here.
                showSickCapAlert = true
            }
            dismiss()
            return
        }

        let finalClockIn: Date
        let finalClockOut: Date

        if useDirectHours {
            finalClockIn = day.addingTimeInterval(8 * 3600)
            finalClockOut = finalClockIn.addingTimeInterval(directHours * 3600)
        } else {
            let resolved = WorkSession.resolveClockPair(clockIn: clockIn, clockOut: clockOut)
            finalClockIn = resolved.clockIn
            finalClockOut = resolved.clockOut
        }

        viewModel.addManualSession(
            date: day,
            clockIn: finalClockIn,
            clockOut: finalClockOut,
            notes: notes.isEmpty ? nil : notes,
            breakMinutes: breakMinutes,
            dayType: dayType,
            isNightShift: isNightShift
        )
        viewModel.showSuccessToast(L10n.feedbackSessionSaved)
        dismiss()
    }
}
