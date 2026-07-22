import SwiftUI

enum TimesheetImportMode: String, CaseIterable, Identifiable {
    case form
    case freeText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .form: return L10n.gridModeForm
        case .freeText: return L10n.gridModeFreeText
        }
    }
}

/// One editable row in the blank timesheet grid.
struct TimesheetGridRow: Identifiable, Equatable {
    let id: UUID
    var date: Date
    var clockIn: Date?
    var clockOut: Date?

    init(id: UUID = UUID(), date: Date, clockIn: Date? = nil, clockOut: Date? = nil) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.clockIn = clockIn
        self.clockOut = clockOut
    }

    var isFilled: Bool {
        guard let clockIn, let clockOut else { return false }
        return clockOut != clockIn
    }

    func toDraft(calendar: Calendar = .current) -> ScannedSessionDraft? {
        guard let clockIn, let clockOut else { return nil }
        let day = calendar.startOfDay(for: date)
        let resolvedIn = Self.combining(time: clockIn, onto: day, calendar: calendar)
        let resolvedOut = Self.combining(time: clockOut, onto: day, calendar: calendar)
        let pair = WorkSession.resolveClockPair(clockIn: resolvedIn, clockOut: resolvedOut)
        guard pair.clockOut > pair.clockIn else { return nil }
        return ScannedSessionDraft(
            date: day,
            clockIn: pair.clockIn,
            clockOut: pair.clockOut,
            notes: nil,
            isSelected: true,
            confidence: 1,
            needsManualReview: false
        )
    }

    private static func combining(time: Date, onto day: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }
}

@MainActor
final class BlankTimesheetViewModel: ObservableObject {
    @Published var mode: TimesheetImportMode = .form
    @Published var rows: [TimesheetGridRow] = []
    @Published var periodAnchor: Date = Date()
    @Published var freeText: String = ""
    @Published var isAnalyzing = false
    @Published var analyzeError: String?
    @Published var analyzeNotice: String?

    private let calendar = Calendar.current

    func loadPeriod(startDay: Int) {
        let period = HistoryPeriodHelper.payrollPeriod(
            containing: Date(),
            startDay: startDay,
            calendar: calendar
        )
        periodAnchor = period.labelMonth
        rows = period.days.map { TimesheetGridRow(date: $0) }
    }

    func shiftPeriod(by months: Int, startDay: Int) {
        periodAnchor = HistoryPeriodHelper.shiftPayrollAnchor(periodAnchor, by: months, calendar: calendar)
        let period = HistoryPeriodHelper.payrollPeriod(
            forMonthAnchor: periodAnchor,
            startDay: startDay,
            calendar: calendar
        )
        rows = period.days.map { day in
            if let existing = rows.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                return TimesheetGridRow(
                    id: existing.id,
                    date: day,
                    clockIn: existing.clockIn,
                    clockOut: existing.clockOut
                )
            }
            return TimesheetGridRow(date: day)
        }
    }

    var filledCount: Int {
        rows.filter(\.isFilled).count
    }

    var filledDrafts: [ScannedSessionDraft] {
        rows.compactMap { $0.toDraft(calendar: calendar) }
    }

    func addRow() {
        let last = rows.last?.date ?? Date()
        let next = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        rows.append(TimesheetGridRow(date: next))
    }

    func removeRow(_ row: TimesheetGridRow) {
        rows.removeAll { $0.id == row.id }
    }

    func defaultClockIn(on day: Date) -> Date {
        calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
    }

    func defaultClockOut(on day: Date) -> Date {
        calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day)
            ?? day.addingTimeInterval(9 * 3600)
    }

    /// Parse free-form text and place matched days/hours into the ruled form.
    func analyzeFreeText(startDay: Int) async {
        let trimmed = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            analyzeError = L10n.gridAnalyzeEmpty
            analyzeNotice = nil
            return
        }

        isAnalyzing = true
        analyzeError = nil
        analyzeNotice = nil
        defer { isAnalyzing = false }

        let result = await TimesheetScannerManager.shared.parseResult(from: trimmed)
        guard !result.usedManualFallback, !result.drafts.isEmpty else {
            analyzeError = L10n.gridAnalyzeFailed
            return
        }

        apply(drafts: result.drafts, startDay: startDay)
        mode = .form
        analyzeNotice = L10n.gridAnalyzeSuccess(result.drafts.count)
    }

    private func apply(drafts: [ScannedSessionDraft], startDay: Int) {
        let sorted = drafts.sorted { $0.date < $1.date }
        if let first = sorted.first {
            let period = HistoryPeriodHelper.payrollPeriod(
                containing: first.date,
                startDay: startDay,
                calendar: calendar
            )
            periodAnchor = period.labelMonth
            var nextRows = period.days.map { TimesheetGridRow(date: $0) }
            for draft in sorted {
                if let index = nextRows.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: draft.date) }) {
                    nextRows[index].clockIn = draft.clockIn
                    nextRows[index].clockOut = draft.clockOut
                } else {
                    nextRows.append(
                        TimesheetGridRow(date: draft.date, clockIn: draft.clockIn, clockOut: draft.clockOut)
                    )
                }
            }
            nextRows.sort { $0.date < $1.date }
            rows = nextRows
        }
    }
}

/// Import hub: ruled blank form and free-text analyze → hours.
struct BlankTimesheetEntryView: View {
    @ObservedObject var appViewModel: AppViewModel
    @StateObject private var gridVM = BlankTimesheetViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @State private var conflictQueue: [Date] = []
    @State private var allConflictDates: [Date] = []
    @State private var overwriteDays: Set<Date> = []
    @State private var showConflictAlert = false
    @State private var currentConflictDay: Date?
    @State private var pendingImportDrafts: [ScannedSessionDraft] = []

    private let ink = Color.primary
    private let rule = Color.primary.opacity(0.55)
    private let headerFill = Color.primary
    private let paper = Color(.systemBackground)
    private let altRow = Color(.secondarySystemBackground).opacity(0.55)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                if gridVM.mode == .form {
                    periodChrome
                    if let notice = gridVM.analyzeNotice {
                        Text(notice)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    hintBar
                    ScrollView {
                        timesheetCard
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 20)
                    }
                    saveBar
                } else {
                    freeTextPane
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.gridTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.editCancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "doc.viewfinder")
                    }
                    .accessibilityLabel(L10n.gridScan)
                }
            }
            .onAppear {
                if gridVM.rows.isEmpty {
                    gridVM.loadPeriod(startDay: appViewModel.settings.payrollStartDay)
                }
            }
            .sheet(isPresented: $showScanner) {
                TimesheetScannerView(appViewModel: appViewModel)
            }
            .overlay {
                conflictOverlay
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: $gridVM.mode) {
            ForEach(TimesheetImportMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(paper)
    }

    private var periodChrome: some View {
        let period = HistoryPeriodHelper.payrollPeriod(
            forMonthAnchor: gridVM.periodAnchor,
            startDay: appViewModel.settings.payrollStartDay
        )
        return HStack {
            Button {
                gridVM.shiftPeriod(by: -1, startDay: appViewModel.settings.payrollStartDay)
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }

            VStack(spacing: 2) {
                Text(HistoryPeriodHelper.payrollPeriodTitle(for: period))
                    .font(.subheadline.weight(.semibold))
                Text(HistoryPeriodHelper.shortRangeLabel(for: period))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                gridVM.shiftPeriod(by: 1, startDay: appViewModel.settings.payrollStartDay)
            } label: {
                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(paper)
    }

    private var hintBar: some View {
        Text(L10n.gridHint)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private var freeTextPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.gridFreeTextHint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            TextEditor(text: $gridVM.freeText)
                .font(.body.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ink, lineWidth: 2)
                }
                .padding(.horizontal, 16)
                .disabled(gridVM.isAnalyzing)

            if let error = gridVM.analyzeError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            Text(L10n.gridFreeTextExample)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)

            Spacer(minLength: 0)

            Button {
                Task {
                    await gridVM.analyzeFreeText(startDay: appViewModel.settings.payrollStartDay)
                }
            } label: {
                HStack {
                    if gridVM.isAnalyzing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(L10n.gridAnalyze)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(gridVM.isAnalyzing || gridVM.freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var timesheetCard: some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(Array(gridVM.rows.enumerated()), id: \.element.id) { index, row in
                gridRow(row, striped: index % 2 == 1)
                if index < gridVM.rows.count - 1 {
                    Rectangle()
                        .fill(rule)
                        .frame(height: 1)
                }
            }
            addRowButton
        }
        .background(paper)
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(ink, lineWidth: 2.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell(L10n.gridColDay, width: 44)
            verticalRule(onHeader: true)
            headerCell(L10n.gridColDate, flex: true)
            verticalRule(onHeader: true)
            headerCell(L10n.gridColIn, flex: true)
            verticalRule(onHeader: true)
            headerCell(L10n.gridColOut, flex: true)
        }
        .background(headerFill)
    }

    private func headerCell(_ title: String, width: CGFloat? = nil, flex: Bool = false) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(.systemBackground))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: flex ? nil : width, alignment: .center)
            .frame(maxWidth: flex ? .infinity : nil, alignment: .center)
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
    }

    private func gridRow(_ row: TimesheetGridRow, striped: Bool) -> some View {
        HStack(spacing: 0) {
            Text(HistoryPeriodHelper.weekdayLetter(for: row.date))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .frame(width: 44)
                .padding(.vertical, 8)

            verticalRule()

            DatePicker(
                "",
                selection: bindingDate(for: row),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.vertical, 4)

            verticalRule()

            timeCell(
                value: row.clockIn,
                onFill: { fillDefaults(for: row) },
                onSet: { setClockIn(row, $0) },
                onClear: { clearClockIn(row) }
            )

            verticalRule()

            timeCell(
                value: row.clockOut,
                onFill: { fillDefaults(for: row) },
                onSet: { setClockOut(row, $0) },
                onClear: { clearClockOut(row) }
            )
        }
        .background(striped ? altRow : paper)
        .contextMenu {
            Button(L10n.gridClearRow, role: .destructive) {
                clearRow(row)
            }
            if gridVM.rows.count > 1 {
                Button(L10n.editDelete, role: .destructive) {
                    gridVM.removeRow(row)
                }
            }
        }
    }

    private func timeCell(
        value: Date?,
        onFill: @escaping () -> Void,
        onSet: @escaping (Date) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        Group {
            if let value {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { value },
                        set: { onSet($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .contextMenu {
                    Button(L10n.gridClearTime, role: .destructive, action: onClear)
                }
            } else {
                Button(action: onFill) {
                    Text(L10n.gridEmptyTime)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func verticalRule(onHeader: Bool = false) -> some View {
        Rectangle()
            .fill(onHeader ? Color(.systemBackground).opacity(0.35) : rule)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private var addRowButton: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(rule)
                .frame(height: 1)
            Button {
                gridVM.addRow()
            } label: {
                Label(L10n.gridAddRow, systemImage: "plus")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private var saveBar: some View {
        VStack(spacing: 10) {
            Button {
                showScanner = true
            } label: {
                Label(L10n.gridScan, systemImage: "doc.viewfinder")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)

            Button {
                beginApproveFlow()
            } label: {
                Text(L10n.gridSave(gridVM.filledCount))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(gridVM.filledCount == 0)
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var conflictOverlay: some View {
        if showConflictAlert, let day = currentConflictDay {
            ImportConflictPopup(
                dates: allConflictDates,
                currentDate: day,
                onReplace: {
                    overwriteDays.insert(Calendar.current.startOfDay(for: day))
                    advanceConflictQueue()
                },
                onApplyAll: {
                    for conflictDay in allConflictDates {
                        overwriteDays.insert(Calendar.current.startOfDay(for: conflictDay))
                    }
                    conflictQueue = []
                    currentConflictDay = nil
                    showConflictAlert = false
                    commitImport()
                },
                onKeep: {
                    advanceConflictQueue()
                }
            )
        }
    }

    // MARK: - Mutations

    private func bindingDate(for row: TimesheetGridRow) -> Binding<Date> {
        Binding(
            get: {
                gridVM.rows.first(where: { $0.id == row.id })?.date ?? row.date
            },
            set: { newDate in
                guard let index = gridVM.rows.firstIndex(where: { $0.id == row.id }) else { return }
                gridVM.rows[index].date = Calendar.current.startOfDay(for: newDate)
            }
        )
    }

    private func fillDefaults(for row: TimesheetGridRow) {
        guard let index = gridVM.rows.firstIndex(where: { $0.id == row.id }) else { return }
        let day = gridVM.rows[index].date
        if gridVM.rows[index].clockIn == nil {
            gridVM.rows[index].clockIn = gridVM.defaultClockIn(on: day)
        }
        if gridVM.rows[index].clockOut == nil {
            gridVM.rows[index].clockOut = gridVM.defaultClockOut(on: day)
        }
    }

    private func setClockIn(_ row: TimesheetGridRow, _ time: Date) {
        guard let index = gridVM.rows.firstIndex(where: { $0.id == row.id }) else { return }
        gridVM.rows[index].clockIn = time
    }

    private func setClockOut(_ row: TimesheetGridRow, _ time: Date) {
        guard let index = gridVM.rows.firstIndex(where: { $0.id == row.id }) else { return }
        gridVM.rows[index].clockOut = time
    }

    private func clearClockIn(_ row: TimesheetGridRow) {
        guard let index = gridVM.rows.firstIndex(where: { $0.id == row.id }) else { return }
        gridVM.rows[index].clockIn = nil
    }

    private func clearClockOut(_ row: TimesheetGridRow) {
        guard let index = gridVM.rows.firstIndex(where: { $0.id == row.id }) else { return }
        gridVM.rows[index].clockOut = nil
    }

    private func clearRow(_ row: TimesheetGridRow) {
        guard let index = gridVM.rows.firstIndex(where: { $0.id == row.id }) else { return }
        gridVM.rows[index].clockIn = nil
        gridVM.rows[index].clockOut = nil
    }

    // MARK: - Import

    private func beginApproveFlow() {
        let drafts = gridVM.filledDrafts
        guard !drafts.isEmpty else { return }
        pendingImportDrafts = drafts
        overwriteDays = []
        allConflictDates = appViewModel.conflictingDays(for: drafts)
        conflictQueue = allConflictDates
        if conflictQueue.isEmpty {
            commitImport()
        } else {
            presentNextConflict()
        }
    }

    private func presentNextConflict() {
        if let next = conflictQueue.first {
            currentConflictDay = next
            showConflictAlert = true
        } else {
            currentConflictDay = nil
            showConflictAlert = false
            commitImport()
        }
    }

    private func advanceConflictQueue() {
        if !conflictQueue.isEmpty {
            conflictQueue.removeFirst()
        }
        if conflictQueue.isEmpty {
            currentConflictDay = nil
            showConflictAlert = false
            commitImport()
        } else {
            presentNextConflict()
        }
    }

    private func commitImport() {
        guard let count = appViewModel.importScannedSessions(
            pendingImportDrafts,
            overwriteDays: overwriteDays,
            markAsAIImported: false
        ) else { return }
        if count > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        dismiss()
    }
}
