import SwiftUI
import UIKit

struct ExportView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedFormat: ExportFormat = .pdf
    @State private var selectedLanguage: ExportLanguage = .phone
    @State private var rangeMode: RangeMode = .all
    @State private var selectedMonth = Date()
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var exportedURL: URL?
    @State private var showShareSheet = false
    @State private var errorMessage: String?

    enum RangeMode: CaseIterable, Identifiable {
        case all
        case month
        case custom

        var id: Self { self }

        var label: String {
            switch self {
            case .all: return L10n.exportAllDays
            case .month: return L10n.exportSpecificMonth
            case .custom: return L10n.exportCustomRange
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.exportDateRange) {
                    Picker(L10n.exportRange, selection: $rangeMode) {
                        ForEach(RangeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    if rangeMode == .month {
                        DatePicker(L10n.exportMonth, selection: $selectedMonth, displayedComponents: .date)
                    }

                    if rangeMode == .custom {
                        DatePicker(L10n.exportFrom, selection: $customFrom, displayedComponents: .date)
                        DatePicker(L10n.exportTo, selection: $customTo, displayedComponents: .date)
                    }
                }

                Section(L10n.exportFormat) {
                    Picker(L10n.exportFormat, selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.localizedName).tag(format)
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

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(L10n.exportTitle)
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedURL {
                    ShareSheet(items: [url])
                }
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
            exportedURL = url
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildRange() -> ExportDateRange {
        switch rangeMode {
        case .all:
            return .all
        case .month:
            let components = Calendar.current.dateComponents([.year, .month], from: selectedMonth)
            return .month(year: components.year ?? 2026, month: components.month ?? 1)
        case .custom:
            return .custom(from: customFrom, to: customTo)
        }
    }
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
