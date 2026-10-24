import SwiftUI

/// Settings → Workplace → employment: contractor (עובד קבלן) or direct (עובד חברה), the
/// 9-month mark, the move from contractor to the company with its new terms, and the
/// pension / severance percentages that start with direct employment. Edits go to the
/// Settings draft and are saved with the rest of Settings.
struct EmploymentSettingsRows: View {
    @Binding var draft: WorkplaceSettings
    @State private var showMove = false

    private var type: EmploymentType? { draft.employment.type }

    var body: some View {
        Group {
            Picker(L10n.employmentTypeLabel, selection: typeBinding) {
                Text(L10n.employmentNotSet).tag(EmploymentType?.none)
                Text(L10n.employmentContractor).tag(EmploymentType?.some(.contractor))
                Text(L10n.employmentDirect).tag(EmploymentType?.some(.direct))
            }
            .accessibilityIdentifier("settings.employmentType")

            if type != nil {
                startDateRow
            }
            if type == .contractor {
                TextField(L10n.settingsContractor, text: Binding(
                    get: { draft.contractorName ?? "" },
                    set: { draft.contractorName = $0.isEmpty ? nil : $0 }
                ))
                .accessibilityIdentifier("settings.contractor")
                contractorLimitRow
                Button { showMove = true } label: {
                    Label(L10n.employmentMoveButton, systemImage: "arrow.right.circle.fill")
                }
                .accessibilityIdentifier("settings.employmentMove")
            }
            if type == .direct {
                if let hire = draft.employment.directHireDate, let old = draft.employment.contractorTerms {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: L10n.employmentHistoryFormat,
                                    AppLocale.makeDateFormatter(dateStyle: .medium).string(from: hire)))
                        Text(String(format: L10n.employmentHistoryTerms,
                                    PayFormatter.string(old.hourlyRate, currencyCode: draft.currencyCode),
                                    PayFormatter.string(old.dailyGasAllowance, currencyCode: draft.currencyCode)))
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    Button { showMove = true } label: {
                        Label(L10n.employmentEditMove, systemImage: "pencil")
                    }
                }
                EmploymentPensionRows(draft: $draft)
            }
        }
        .sheet(isPresented: $showMove) {
            EmploymentMoveSheet(draft: $draft)
        }
    }

    private var typeBinding: Binding<EmploymentType?> {
        Binding(
            get: { draft.employment.type },
            set: { draft.employment.type = $0 }
        )
    }

    private var startDateRow: some View {
        HStack {
            Text(L10n.employmentStartDate)
            Spacer()
            if let start = draft.employment.startDate {
                DatePicker("", selection: Binding(
                    get: { start },
                    set: { draft.employment.startDate = Calendar.current.startOfDay(for: $0) }
                ), displayedComponents: .date)
                .labelsHidden()
                Button { draft.employment.startDate = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button(L10n.employmentSetDate) {
                    draft.employment.startDate = Calendar.current.startOfDay(for: Date())
                }
            }
        }
    }

    /// "Reaches 9 months on …" with the days left, or a gentle note once passed.
    @ViewBuilder
    private var contractorLimitRow: some View {
        if let limit = draft.employment.contractorLimitDate,
           let days = draft.employment.daysUntilContractorLimit() {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: L10n.employmentNineMonths,
                            AppLocale.makeDateFormatter(dateStyle: .medium).string(from: limit)))
                Text(days >= 0 ? String(format: L10n.employmentDaysLeft, days) : L10n.employmentNineMonthsPassed)
                    .foregroundStyle(days >= 0 && days > 30 ? Color.secondary : Color.orange)
            }
            .font(.footnote)
        }
    }
}

private struct EmploymentPensionRows: View {
    @Binding var draft: WorkplaceSettings

    var body: some View {
        Group {
            Toggle(L10n.employmentPensionToggle, isOn: $draft.employment.pensionEnabled)
            if draft.employment.pensionEnabled {
                percentRow(L10n.employmentPensionEmployee, value: $draft.employment.pension.employeePercent)
                percentRow(L10n.employmentPensionEmployer, value: $draft.employment.pension.employerPercent)
                percentRow(L10n.employmentSeverance, value: $draft.employment.pension.severancePercent)
                Text(L10n.employmentPensionHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percentRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text("%").foregroundStyle(.secondary)
        }
    }
}

/// "The company hired me directly": the date and the new hourly rate / travel
/// allowance. Shifts before that date keep the contractor-era terms.
private struct EmploymentMoveSheet: View {
    @Binding var draft: WorkplaceSettings
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var rate: Double = 0
    @State private var gas: Double = 0
    @State private var pensionOn = true
    @State private var pension = PensionTerms()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L10n.employmentMoveDate, selection: $date, displayedComponents: .date)
                    amountRow(L10n.employmentMoveRate, value: $rate)
                    amountRow(L10n.employmentMoveGas, value: $gas)
                } footer: {
                    Text(L10n.employmentMoveNote)
                }
                Section {
                    Toggle(L10n.employmentPensionToggle, isOn: $pensionOn)
                    if pensionOn {
                        percentRow(L10n.employmentPensionEmployee, value: $pension.employeePercent)
                        percentRow(L10n.employmentPensionEmployer, value: $pension.employerPercent)
                        percentRow(L10n.employmentSeverance, value: $pension.severancePercent)
                    }
                } footer: {
                    Text(L10n.employmentPensionHint)
                }
            }
            .navigationTitle(L10n.employmentMoveTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.editCancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.editSave) { apply(); dismiss() }.disabled(rate <= 0)
                }
            }
        }
        .tint(HomeAccentTheme.shared.accent)
        .onAppear {
            if let existing = draft.employment.directHireDate { date = existing }
            rate = draft.hourlyRate
            gas = draft.dailyGasAllowance
            if draft.employment.directHireDate != nil {
                pensionOn = draft.employment.pensionEnabled
            }
            pension = draft.employment.pension
        }
        .presentationDetents([.large])
    }

    private func percentRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text("%").foregroundStyle(.secondary)
        }
    }

    private func amountRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text(PayFormatter.symbol(for: draft.currencyCode)).foregroundStyle(.secondary)
        }
    }

    private func apply() {
        let day = Calendar.current.startOfDay(for: date)
        if draft.employment.contractorTerms == nil {
            // First move: what's in Settings now were the contractor's terms.
            draft.employment.contractorTerms = ContractorTerms(
                hourlyRate: draft.hourlyRate,
                dailyGasAllowance: draft.dailyGasAllowance,
                contractorName: draft.contractorName
            )
        }
        draft.employment.type = .direct
        draft.employment.directHireDate = day
        draft.employment.pensionEnabled = pensionOn
        draft.employment.pension = pension
        draft.hourlyRate = rate
        draft.dailyGasAllowance = gas
        draft.contractorName = nil
    }
}
