import SwiftUI

/// Settings → Work rules → Holidays. Lets the worker add, remove, rename or move
/// holidays for the workplace being edited. Edits go to the Settings draft binding
/// and are saved with the rest of Settings.
struct HolidaysSettingsLink: View {
    @Binding var customization: HolidayCustomization

    var body: some View {
        NavigationLink {
            HolidaysEditorView(customization: $customization)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(L10n.holidaysTitle, systemImage: "star.circle")
                Text(L10n.holidaysSettingsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("settings.holidays")
    }
}

struct HolidaysEditorView: View {
    @Binding var customization: HolidayCustomization
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var editing: HolidayDraft?

    private struct Row: Identifiable {
        let id: String
        let date: Date
        let name: String
        let affectsPay: Bool
        let isCustom: Bool
    }

    var body: some View {
        List {
            Section {
                Stepper(value: $year, in: 2000...2100) {
                    Text(String(year)).font(.headline.monospacedDigit())
                }
                if rows.isEmpty {
                    Text(L10n.holidaysEmpty).foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    Button { startEditing(row) } label: { rowLabel(row) }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button(role: .destructive) { remove(row) } label: {
                                Label(L10n.holidaysRemove, systemImage: "trash")
                            }
                        }
                }
            } footer: {
                Text(L10n.holidaysFooter)
            }
            Section {
                Button {
                    editing = HolidayDraft(originalBundledDate: nil, id: nil, name: "", date: defaultNewDate, affectsPay: true)
                } label: {
                    Label(L10n.holidaysAdd, systemImage: "plus.circle.fill")
                }
                if !customization.isEmpty {
                    Button(role: .destructive) {
                        customization = HolidayCustomization()
                    } label: {
                        Label(L10n.holidaysReset, systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .navigationTitle(L10n.holidaysTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { draft in
            HolidayEditSheet(draft: draft) { commit($0) }
                .presentationDetents([.medium])
                .tint(HomeAccentTheme.shared.accent)
        }
    }

    private var defaultNewDate: Date {
        let calendar = Calendar.current
        return calendar.date(from: DateComponents(year: year, month: calendar.component(.month, from: Date()), day: calendar.component(.day, from: Date())))
            ?? Date()
    }

    private func rowLabel(_ row: Row) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                Text(AppLocale.makeDateFormatter(dateStyle: .full).string(from: row.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if row.isCustom {
                Text(L10n.holidaysCustomTag)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if !row.affectsPay {
                Image(systemName: "calendar").foregroundStyle(.secondary)
            }
        }
    }

    private var rows: [Row] {
        let calendar = Calendar.current
        var result: [Row] = []
        for (date, holiday) in IsraeliHolidayCalendar.bundledHolidays(inYear: year, calendar: calendar) {
            if customization.isHidden(date, calendar: calendar) || customization.customHoliday(on: date, calendar: calendar) != nil {
                continue
            }
            let name = AppLocale.current == .hebrew ? holiday.hebrewName : holiday.englishName
            result.append(Row(id: "b-\(date.timeIntervalSince1970)", date: date, name: name, affectsPay: holiday.affectsPay, isCustom: false))
        }
        for custom in customization.custom where calendar.component(.year, from: custom.date) == year {
            result.append(Row(id: "c-\(custom.id)", date: custom.date, name: custom.name, affectsPay: custom.affectsPay, isCustom: true))
        }
        return result.sorted { $0.date < $1.date }
    }

    private func startEditing(_ row: Row) {
        if row.isCustom, let custom = customization.custom.first(where: { "c-\($0.id)" == row.id }) {
            editing = HolidayDraft(originalBundledDate: nil, id: custom.id, name: custom.name, date: custom.date, affectsPay: custom.affectsPay)
        } else {
            editing = HolidayDraft(originalBundledDate: row.date, id: nil, name: row.name, date: row.date, affectsPay: row.affectsPay)
        }
    }

    private func remove(_ row: Row) {
        if row.isCustom {
            customization.custom.removeAll { "c-\($0.id)" == row.id }
        } else {
            customization.hiddenDates.append(row.date)
        }
    }

    private func commit(_ draft: HolidayDraft) {
        let calendar = Calendar.current
        if let original = draft.originalBundledDate, !customization.isHidden(original, calendar: calendar) {
            customization.hiddenDates.append(calendar.startOfDay(for: original))
        }
        // One custom holiday per day: replace anything already on the target day.
        customization.custom.removeAll {
            $0.id == draft.id || calendar.isDate($0.date, inSameDayAs: draft.date)
        }
        customization.custom.append(
            CustomHoliday(id: draft.id ?? UUID(), date: draft.date, name: draft.name, affectsPay: draft.affectsPay)
        )
        // A custom day shadows the bundled holiday on that date, so un-hiding isn't needed.
        year = calendar.component(.year, from: draft.date)
    }
}

struct HolidayDraft: Identifiable {
    let originalBundledDate: Date?
    let id: UUID?
    var name: String
    var date: Date
    var affectsPay: Bool

    var sheetID: String { id?.uuidString ?? originalBundledDate.map { "b\($0.timeIntervalSince1970)" } ?? "new" }
}

private struct HolidayEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: HolidayDraft
    let onSave: (HolidayDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.holidaysName, text: $draft.name, prompt: Text(L10n.holidaysNamePlaceholder))
                DatePicker(L10n.holidaysDate, selection: $draft.date, displayedComponents: .date)
                Toggle(L10n.holidaysPaysRate, isOn: $draft.affectsPay)
            }
            .navigationTitle(draft.id == nil && draft.originalBundledDate == nil ? L10n.holidaysAdd : L10n.holidaysEdit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.editCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.editSave) {
                        var saved = draft
                        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved.date = Calendar.current.startOfDay(for: saved.date)
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
