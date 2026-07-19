import SwiftUI
import UIKit

struct ExportView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedFormat: ExportFormat = .pdf
    @State private var selectedLanguage: ExportLanguage = .phone
    @State private var rangeMode: RangeMode = .thisMonth
    @State private var selectedMonth = Date()
    @State private var customFrom = AppLocale.calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var shareItem: ShareableFile?
    @State private var errorMessage: String?

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
            startDay: viewModel.settings.payrollStartDay,
            calendar: AppLocale.calendar
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
                    .accessibilityIdentifier("phone.export.range")

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
                    .accessibilityIdentifier("phone.export.format")
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
                    .accessibilityIdentifier("phone.export.submit")
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
                language: selectedLanguage
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
            let components = AppLocale.calendar.dateComponents([.year, .month], from: selectedMonth)
            return .month(year: components.year ?? 2026, month: components.month ?? 1)
        case .thisYear:
            let year = AppLocale.calendar.component(.year, from: Date())
            return .year(year)
        case .custom:
            return .custom(from: customFrom, to: customTo)
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
