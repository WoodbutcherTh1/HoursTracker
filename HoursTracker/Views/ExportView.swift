import SwiftUI
import UIKit

struct ExportView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    @State private var selectedFormat: ExportFormat = .pdf
    @State private var selectedLanguage: ExportLanguage = .phone
    @State private var dayTypeFilter: ExportDayTypeFilter = .all
    @State private var rangeMode: RangeMode = .thisMonth
    @State private var selectedMonth = Date()
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var shareItem: ShareableFile?
    @State private var errorMessage: String?
    /// "Attach notes" — remembered between exports.
    @AppStorage("exportIncludeNotes") private var includeNotes = false

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

                Section {
                    Toggle(isOn: $includeNotes) {
                        Label(L10n.exportIncludeNotes, systemImage: "note.text")
                    }
                    .accessibilityIdentifier("export.includeNotes")
                } footer: {
                    Text(L10n.exportIncludeNotesHint)
                }

                Section(L10n.exportLanguage) {
                    Picker(L10n.exportLanguage, selection: $selectedLanguage) {
                        ForEach(ExportLanguage.allCases) { language in
                            Text(label(for: language)).tag(language)
                        }
                    }
                }

                // Live preview of exactly what the current options would export
                // (same range filtering + pay engine as the report itself).
                Section {
                    if let summary = previewSummary {
                        HStack(spacing: 12) {
                            previewStat(value: "\(summary.dayCount)", label: L10n.exportPreviewDays)
                            previewStat(
                                value: String(format: "%.1f", summary.totalHours),
                                label: L10n.exportPreviewHours
                            )
                            previewStat(
                                value: PayFormatter.string(summary.gross, currencyCode: viewModel.settings.currencyCode),
                                label: L10n.exportPreviewGross
                            )
                            previewStat(
                                value: PayFormatter.string(summary.net, currencyCode: viewModel.settings.currencyCode),
                                label: L10n.exportPreviewNet
                            )
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label(L10n.exportPreviewEmpty, systemImage: "calendar.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L10n.exportPreviewTitle)
                }

                Section {
                    Button {
                        export()
                    } label: {
                        Label(L10n.exportReport, systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HomeNeon.accent)
                    .foregroundStyle(.black)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(appBackground.background.ignoresSafeArea())
            .navigationTitle(L10n.exportTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AssistantToolbarButton(onOpen: { viewModel.showAssistant = true })
                }
            }
            .toolbarBackground(appBackground.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
            // The paired Watch cannot present its own share sheet — when it requests
            // an export, MainTabView switches here and this picks up the file the
            // phone already generated and presents the same share sheet the Export
            // button itself uses.
            .onChange(of: viewModel.pendingWatchExport) { _, newValue in
                guard let newValue else { return }
                shareItem = newValue
                viewModel.pendingWatchExport = nil
            }
        }
    }

    // MARK: - Live preview

    /// What the current range + day-type filters would produce, computed with
    /// the same pay engine as the actual report.
    private var previewSummary: (dayCount: Int, totalHours: Double, gross: Double, net: Double)? {
        let range = buildRange()
        let calendar = Calendar.current
        var sessions = viewModel.sessions.filter { $0.clockOut != nil }

        switch range {
        case .all:
            break
        case .month(let year, let month):
            sessions = sessions.filter {
                let c = calendar.dateComponents([.year, .month], from: $0.date)
                return c.year == year && c.month == month
            }
        case .year(let year):
            sessions = sessions.filter { calendar.component(.year, from: $0.date) == year }
        case .custom(let from, let to):
            let start = calendar.startOfDay(for: from)
            let end = calendar.startOfDay(for: to).addingTimeInterval(86400 - 1)
            sessions = sessions.filter { $0.date >= start && $0.date <= end }
        }
        if let dayTypes = dayTypeFilter.dayTypes {
            sessions = sessions.filter { dayTypes.contains($0.dayType) }
        }
        guard !sessions.isEmpty else { return nil }

        let breakdown = OvertimeCalculator.aggregate(sessions: sessions, settings: viewModel.settings)
        let dayCount = Set(sessions.map { calendar.startOfDay(for: $0.date) }).count
        return (dayCount, breakdown.totalHours, breakdown.totalPay, breakdown.netPay)
    }

    private func previewStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .htFont(size: 14, relativeTo: .headline, weight: .bold, design: .rounded)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .htFont(size: 8, relativeTo: .caption2, weight: .semibold, design: .rounded)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
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
        case .russian:
            return L10n.exportLanguageRussian
        }
    }

    private func export() {
        errorMessage = nil
        do {
            let url = try viewModel.export(
                range: buildRange(),
                format: selectedFormat,
                language: selectedLanguage,
                dayTypes: dayTypeFilter.dayTypes,
                includeNotes: includeNotes
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
struct ShareableFile: Identifiable, Equatable {
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
