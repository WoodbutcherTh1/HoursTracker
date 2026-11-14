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
    @AppStorage("exportIncludeNotes") private var includeNotes = false
    @State private var selectedQuickPill: QuickDatePill?

    // Store the summary in @State instead of calculating it in the body.
    @State private var previewSummary: (dayCount: Int, totalHours: Double, gross: Double, net: Double)? = nil
    /// The in-flight preview computation, if any — cancelled and replaced
    /// whenever a filter changes before it finishes, so a slow background
    /// result from a since-superseded filter can never overwrite a newer one.
    @State private var previewTask: Task<Void, Never>?

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
            startDay: viewModel.activeSettings.payrollStartDay
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    quickDatePillsRow

                    unifiedOptionsCard
                        // Recalculate when options change
                        .onChange(of: rangeMode) { _, _ in updatePreview() }
                        .onChange(of: selectedMonth) { _, _ in updatePreview() }
                        .onChange(of: customFrom) { _, _ in updatePreview() }
                        .onChange(of: customTo) { _, _ in updatePreview() }
                        .onChange(of: dayTypeFilter) { _, _ in updatePreview() }

                    ExportReceiptPreview(
                        summary: previewSummary,
                        currencyCode: viewModel.activeSettings.currencyCode,
                        format: selectedFormat
                    )

                    whatsIncludedCard

                    Button {
                        export()
                    } label: {
                        Label(L10n.exportReport, systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "00E5FF"), Color(hex: "26F273")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
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
            .onChange(of: viewModel.pendingWatchExport) { _, newValue in
                guard let newValue else { return }
                shareItem = newValue
                viewModel.pendingWatchExport = nil
            }
            .onAppear {
                updatePreview()
            }
        }
    }

    // MARK: - Data Calculation

    /// Filters sessions for the current range/day-type (cheap, main-thread) then
    /// runs `OvertimeCalculator.aggregate` — a real calculation across every
    /// matching day, not free for a long history — off the main thread, so
    /// dragging the date pickers never competes with touch handling for the
    /// main thread (that contention is what trips "gesture gate timed out").
    /// Any previous in-flight computation is cancelled first, so a slow result
    /// for a filter the user has already changed away from can't land after a
    /// newer one and show stale numbers.
    private func updatePreview() {
        previewTask?.cancel()

        let range = buildRange()
        let calendar = Calendar.current
        var sessions = viewModel.workSessions.filter { $0.clockOut != nil }

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
            let endDay = calendar.startOfDay(for: to)
            guard start <= endDay, let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) else {
                previewSummary = nil
                return
            }
            sessions = sessions.filter { $0.date >= start && $0.date < endExclusive }
        }

        if let dayTypes = dayTypeFilter.dayTypes {
            sessions = sessions.filter { dayTypes.contains($0.dayType) }
        }
        guard !sessions.isEmpty else {
            previewSummary = nil
            return
        }

        let settings = viewModel.activeSettings
        // `Task { }` alone would inherit this method's MainActor context and
        // still run `aggregate` on the main thread — `.detached` is what
        // actually hops off it. `sessions`/`settings`/`calendar` are plain
        // value types (structs), so handing them to another thread is safe;
        // nothing here touches `viewModel` or any other reference type off
        // the main thread.
        previewTask = Task.detached(priority: .userInitiated) {
            let breakdown = OvertimeCalculator.aggregate(sessions: sessions, settings: settings)
            let dayCount = Set(sessions.map { calendar.startOfDay(for: $0.date) }).count
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewSummary = (dayCount, breakdown.totalHours, breakdown.totalPay, breakdown.netPay)
            }
        }
    }

    // MARK: - Quick date pills

    private var quickDatePillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickDatePill.allCases) { pill in
                    quickDatePillButton(pill)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func quickDatePillButton(_ pill: QuickDatePill) -> some View {
        let isSelected = selectedQuickPill == pill
        return Button {
            applyQuickPill(pill)
        } label: {
            Text(pill.label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color(hex: "00E5FF").opacity(0.18) : Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color(hex: "00E5FF") : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 1
                    )
                )
                .foregroundStyle(isSelected ? Color(hex: "00E5FF") : .white.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    private func applyQuickPill(_ pill: QuickDatePill) {
        let calendar = Calendar.current
        let now = Date()
        switch pill {
        case .thisMonth:
            rangeMode = .thisMonth
        case .lastMonth:
            rangeMode = .month
            selectedMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .thisWeek:
            rangeMode = .custom
            if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
                customFrom = interval.start
                customTo = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
            }
        case .lastWeek:
            rangeMode = .custom
            if let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) {
                let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeek.start) ?? thisWeek.start
                customFrom = lastWeekStart
                customTo = calendar.date(byAdding: .day, value: -1, to: thisWeek.start) ?? lastWeekStart
            }
        }
        selectedQuickPill = pill
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func clearQuickPillSelection() {
        selectedQuickPill = nil
    }

    // MARK: - Unified options card

    private var unifiedOptionsCard: some View {
        VStack(spacing: 0) {
            ExportMenuRow(
                icon: "calendar",
                title: L10n.exportRange,
                valueLabel: rangeMode.label,
                options: RangeMode.allCases.map { ($0, $0.label) },
                selection: $rangeMode,
                onSelect: clearQuickPillSelection
            )

            if rangeMode == .thisMonth {
                exportDivider
                HStack {
                    Text(L10n.exportDateRange)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 8)
                    Text(HistoryPeriodHelper.shortRangeLabel(for: currentPayrollPeriod))
                        .foregroundStyle(.white)
                }
                .font(.subheadline)
                .padding(.vertical, 6)
            }

            if rangeMode == .month {
                exportDivider
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.exportMonth)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    MonthYearPicker(selection: $selectedMonth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .onChange(of: selectedMonth) { _, _ in clearQuickPillSelection() }
            }

            if rangeMode == .custom {
                exportDivider
                DatePicker(L10n.exportFrom, selection: $customFrom, displayedComponents: .date)
                    .font(.subheadline)
                    .padding(.vertical, 6)
                    .onChange(of: customFrom) { _, _ in clearQuickPillSelection() }
                exportDivider
                DatePicker(L10n.exportTo, selection: $customTo, displayedComponents: .date)
                    .font(.subheadline)
                    .padding(.vertical, 6)
                    .onChange(of: customTo) { _, _ in clearQuickPillSelection() }
            }

            exportDivider

            ExportMenuRow(
                icon: "doc.text.fill",
                title: L10n.exportFormat,
                valueLabel: selectedFormat.localizedName,
                options: ExportFormat.allCases.map { ($0, $0.localizedName) },
                selection: $selectedFormat
            )

            exportDivider

            ExportMenuRow(
                icon: "line.3.horizontal.decrease.circle",
                title: L10n.exportDayType,
                valueLabel: dayTypeFilter.label,
                options: ExportDayTypeFilter.allCases.map { ($0, $0.label) },
                selection: $dayTypeFilter
            )

            exportDivider

            ExportMenuRow(
                icon: "globe",
                title: L10n.exportLanguage,
                valueLabel: label(for: selectedLanguage),
                options: ExportLanguage.allCases.map { ($0, label(for: $0)) },
                selection: $selectedLanguage
            )

            exportDivider

            VStack(alignment: .leading, spacing: 3) {
                Toggle(isOn: $includeNotes) {
                    Label(L10n.exportIncludeNotes, systemImage: "note.text")
                        .foregroundStyle(.white)
                }
                .tint(Color(hex: "00E5FF"))
                .accessibilityIdentifier("export.includeNotes")

                Text(L10n.exportIncludeNotesHint)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(Color(hex: "0D0D0D"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: "00E5FF").opacity(0.3), lineWidth: 1)
        )
    }

    private var exportDivider: some View {
        Divider().overlay(Color.white.opacity(0.08))
    }

    private var whatsIncludedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.exportWhatsIncludedTitle)
                .dsFont(.sectionHeader)
                .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
                whatsIncludedRow(L10n.exportWhatsIncludedOvertime)
                whatsIncludedRow(L10n.exportWhatsIncludedBreaks)
                whatsIncludedRow(L10n.exportWhatsIncludedDailyBreakdown)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "0D0D0D"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func whatsIncludedRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "26F273"))
            Text(text)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .thai:
            return L10n.exportLanguageThai
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

// MARK: - Supporting Types

private enum QuickDatePill: CaseIterable, Identifiable {
    case thisMonth
    case lastMonth
    case thisWeek
    case lastWeek

    var id: Self { self }

    var label: String {
        switch self {
        case .thisMonth: return L10n.exportThisMonth
        case .lastMonth: return L10n.exportLastMonth
        case .thisWeek: return L10n.exportThisWeek
        case .lastWeek: return L10n.exportLastWeek
        }
    }
}

private struct ExportMenuRow<Value: Hashable>: View {
    let icon: String
    let title: String
    let valueLabel: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var onSelect: (() -> Void)?

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                    onSelect?()
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack {
                Label {
                    Text(title)
                        .foregroundStyle(.white)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(Color(hex: "00E5FF"))
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text(valueLabel)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .contentShape(Rectangle())
        }
        .padding(.vertical, 8)
        .accentColor(.primary)
    }
}

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

private struct ExportReceiptPreview: View {
    let summary: (dayCount: Int, totalHours: Double, gross: Double, net: Double)?
    let currencyCode: String
    let format: ExportFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.exportPreviewTitle.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.4)

            if let summary {
                HStack(spacing: 0) {
                    segment(L10n.exportPreviewDays, "\(summary.dayCount)")
                    pipe
                    segment(L10n.exportPreviewHours, String(format: "%.1f", summary.totalHours))
                    pipe
                    segment(L10n.exportPreviewNet, PayFormatter.string(summary.net, currencyCode: currencyCode), emphasized: true)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .foregroundStyle(Color.white.opacity(0.18))
                )

                readyTag
            } else {
                Label(L10n.exportPreviewEmpty, systemImage: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private func segment(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .htFont(size: emphasized ? 16 : 14, relativeTo: .body, weight: .bold, design: .monospaced)
                .foregroundStyle(emphasized ? Color(hex: "26F273") : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .htFont(size: 9, relativeTo: .caption2, weight: .medium, design: .rounded)
                .tracking(0.3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var pipe: some View {
        Text(verbatim: "|")
            .font(.body.weight(.light))
            .foregroundStyle(.white.opacity(0.15))
    }

    private var readyTag: some View {
        HStack(spacing: 5) {
            Image(systemName: format.icon)
                .font(.caption2.weight(.semibold))
            Text(L10n.exportPreviewReady(format.localizedName))
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Color(hex: "26F273"))
    }
}

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