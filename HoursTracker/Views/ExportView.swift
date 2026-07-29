import SwiftUI
import UIKit

struct ExportView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedFormat: ExportFormat = .pdf
    @State private var selectedLanguage: ExportLanguage = .phone
    @State private var dayTypeFilter: ExportDayTypeFilter = .all
    @State private var rangeMode: RangeMode = .thisMonth
    @State private var selectedMonth = Date()
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var shareItem: ShareableFile?
    @State private var errorMessage: String?
    // Owned here (not inside PayslipLibraryView) so the single .navigationDestination
    // below — declared at the NavigationStack root — can share the same instance the
    // grid observes. See the comment on PayslipLibraryView for why.
    @StateObject private var payslipLibraryViewModel = PayslipLibraryViewModel()
    @State private var payslipDeleteError: String?

    /// Menu order is intentional: This month → Specific month → This year → Custom range.
    enum RangeMode: CaseIterable, Identifiable {
        case thisMonth
        case month
        case thisYear
        case custom

        var id: Self { self }

        var label: String {
            switch self {
            case .thisMonth: return L10n.exportThisMonth
            case .month: return L10n.exportSpecificMonth
            case .thisYear: return L10n.exportThisYear
            case .custom: return L10n.exportCustomRange
            }
        }
    }

    private var currentPayrollPeriod: PayrollPeriod {
        HistoryPeriodHelper.payrollPeriod(
            containing: Date(),
            startDay: viewModel.settings.payrollStartDay
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.exportRange, selection: $rangeMode) {
                        ForEach(RangeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    if rangeMode == .thisMonth {
                        Text(HistoryPeriodHelper.shortRangeLabel(for: currentPayrollPeriod))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if rangeMode == .month {
                        HStack {
                            Text(L10n.exportMonth)
                            Spacer(minLength: 8)
                            MonthYearPicker(selection: $selectedMonth)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if rangeMode == .custom {
                        DatePicker(L10n.exportFrom, selection: $customFrom, displayedComponents: .date)
                        DatePicker(L10n.exportTo, selection: $customTo, displayedComponents: .date)
                    }
                } header: {
                    Text(L10n.exportDateRange)
                }

                Section(L10n.exportFormat) {
                    Picker(L10n.exportFormat, selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.localizedName).tag(format)
                        }
                    }
                }

                Section(L10n.exportDayType) {
                    Picker(L10n.exportDayType, selection: $dayTypeFilter) {
                        ForEach(ExportDayTypeFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                }

                Section(L10n.exportLanguage) {
                    Picker(L10n.exportLanguage, selection: $selectedLanguage) {
                        ForEach(ExportLanguage.allCases) { language in
                            Text(label(for: language)).tag(language)
                        }
                    }
                }

                Section {
                    Button {
                        export()
                    } label: {
                        Label(L10n.exportReport, systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    NavigationLink {
                        PayslipLibraryView(appViewModel: viewModel, viewModel: payslipLibraryViewModel)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.payslipLibraryTitle)
                                    .font(.body.weight(.semibold))
                                Text(L10n.payslipLibraryEntrySubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(L10n.payslipSectionTitle)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(L10n.exportTitle)
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
            // Declared once, at the stack root — see PayslipLibraryView's header comment.
            .navigationDestination(for: PayslipRecord.self) { record in
                PayslipDetailView(
                    record: record,
                    sourceURL: payslipLibraryViewModel.sourceURL(for: record),
                    onDelete: {
                        do {
                            try payslipLibraryViewModel.delete(record)
                            viewModel.showSuccessToast(L10n.payslipDeletedToast)
                            return true
                        } catch {
                            payslipDeleteError = error.localizedDescription
                            return false
                        }
                    }
                )
            }
            .alert(L10n.payslipDeleteFailed, isPresented: Binding(
                get: { payslipDeleteError != nil },
                set: { if !$0 { payslipDeleteError = nil } }
            )) {
                Button(L10n.editCancel, role: .cancel) { payslipDeleteError = nil }
            } message: {
                Text(payslipDeleteError ?? "")
            }
        }
    }

    private func label(for language: ExportLanguage) -> String {
        switch language {
        case .phone:
            return L10n.exportLanguagePhone(AppLocale.current.localizedDisplayName)
        case .english:
            return L10n.exportLanguageEnglish
        case .hebrew:
            return L10n.exportLanguageHebrew
        case .arabic:
            return L10n.exportLanguageArabic
        }
    }

    private func export() {
        errorMessage = nil
        do {
            let url = try viewModel.export(
                range: buildRange(),
                format: selectedFormat,
                language: selectedLanguage,
                dayTypes: dayTypeFilter.dayTypes
            )
            // Present on the next run loop so the sheet always has a non-nil item
            // (avoids the blank first-presentation SwiftUI race).
            DispatchQueue.main.async {
                shareItem = ShareableFile(url: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildRange() -> ExportDateRange {
        switch rangeMode {
        case .thisMonth:
            let period = currentPayrollPeriod
            return .custom(from: period.start, to: period.end)
        case .month:
            let components = Calendar.current.dateComponents([.year, .month], from: selectedMonth)
            return .month(year: components.year ?? 2026, month: components.month ?? 1)
        case .thisYear:
            let year = Calendar.current.component(.year, from: Date())
            return .year(year)
        case .custom:
            return .custom(from: customFrom, to: customTo)
        }
    }
}

/// Which day types to include in the exported file. `.holiday` bundles rest
/// days in with holidays since both pay the same 150%+ premium tiers.
enum ExportDayTypeFilter: CaseIterable, Identifiable {
    case all
    case regular
    case holiday
    case sick

    var id: Self { self }

    var dayTypes: Set<DayType>? {
        switch self {
        case .all: return nil
        case .regular: return [.regular]
        case .holiday: return [.restDay, .holiday]
        case .sick: return [.sick]
        }
    }

    var label: String {
        switch self {
        case .all: return L10n.exportDayTypeAll
        case .regular: return L10n.dayTypeRegular
        case .holiday: return L10n.dayTypeHoliday
        case .sick: return L10n.dayTypeSick
        }
    }
}

/// Identifiable file handle for `.sheet(item:)` share presentation.
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            for item in items {
                if let url = item as? URL {
                    ExportTempFileStore.remove(url)
                }
            }
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
