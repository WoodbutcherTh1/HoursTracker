import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HistoryView: View {
    @ObservedObject var viewModel: AppViewModel

    /// Anchor month for the payroll cycle label / chevron navigation.
    @State private var periodAnchor: Date = Date()
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    /// Page index into `periodWeeks` for the Health-style week strip.
    @State private var selectedWeekIndex: Int = 0
    @State private var payMode: PayDisplayMode = .net
    @State private var selectedSession: WorkSession?
    @State private var editingSession: WorkSession?
    @State private var sessionPendingDelete: WorkSession?
    @State private var menuSession: WorkSession?
    @State private var showScanner = false
    @State private var showManualEntry = false
    @State private var shareItem: ShareableFile?
    @State private var exportError: String?
    @State private var copyToastVisible = false

    private let calendar = Calendar.current

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private var activePeriod: PayrollPeriod {
        HistoryPeriodHelper.payrollPeriod(
            forMonthAnchor: periodAnchor,
            startDay: viewModel.settings.payrollStartDay,
            calendar: calendar
        )
    }

    private var periodWeeks: [PayrollWeek] {
        HistoryPeriodHelper.weekRows(for: activePeriod, calendar: calendar)
    }

    /// Weekday initials for the column order (locale `firstWeekday`).
    private var weekdayHeaderLetters: [String] {
        guard let week = periodWeeks.first else { return [] }
        return week.days.map { HistoryPeriodHelper.weekdayLetter(for: $0.date) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                historyChrome
                sessionsContent
                stickySummaryBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.historyTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "tablecells")
                    }
                    .accessibilityLabel(L10n.gridTitle)

                    Button {
                        showManualEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedSession) { session in
                ShiftDetailSheet(
                    session: session,
                    breakdown: viewModel.breakdown(for: session),
                    viewModel: viewModel
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingSession) { session in
                EditSessionView(viewModel: viewModel, session: session) {
                    editingSession = nil
                }
            }
            .sheet(isPresented: $showScanner) {
                BlankTimesheetEntryView(appViewModel: viewModel)
            }
            .sheet(isPresented: $showManualEntry) {
                NavigationStack {
                    ManualEntryView(viewModel: viewModel)
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
            .alert(
                L10n.editDeleteConfirm,
                isPresented: Binding(
                    get: { sessionPendingDelete != nil },
                    set: { if !$0 { sessionPendingDelete = nil } }
                )
            ) {
                Button(L10n.editDelete, role: .destructive) {
                    if let session = sessionPendingDelete {
                        viewModel.deleteSession(session)
                        viewModel.showSuccessToast(L10n.feedbackSessionDeleted)
                    }
                    sessionPendingDelete = nil
                }
                Button(L10n.editCancel, role: .cancel) {
                    sessionPendingDelete = nil
                }
            }
            .confirmationDialog(
                AppLocale.tr("history.rowMenu"),
                isPresented: Binding(
                    get: { menuSession != nil },
                    set: { if !$0 { menuSession = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let session = menuSession {
                    Button(AppLocale.tr("history.copy")) {
                        copySession(session)
                        menuSession = nil
                    }
                    Button(L10n.editTitle) {
                        editingSession = session
                        menuSession = nil
                    }
                    Button(AppLocale.tr("history.exportShift")) {
                        exportSession(session)
                        menuSession = nil
                    }
                    Button(L10n.editDelete, role: .destructive) {
                        sessionPendingDelete = session
                        menuSession = nil
                    }
                }
                Button(L10n.editCancel, role: .cancel) {
                    menuSession = nil
                }
            }
            .alert(
                L10n.errorTitle,
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )
            ) {
                Button(L10n.errorOK, role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .overlay(alignment: .bottom) {
                if copyToastVisible {
                    Text(AppLocale.tr("history.copied"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.green.gradient, in: Capsule())
                        .padding(.bottom, 72)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: copyToastVisible)
            .onAppear {
                alignToCurrentPayrollPeriod()
            }
            .onChange(of: viewModel.settings.payrollStartDay) { _, _ in
                alignToCurrentPayrollPeriod()
            }
            .onChange(of: selectedDay) { _, newDay in
                syncWeekPage(to: newDay, animated: true)
            }
            .onChange(of: periodAnchor) { _, _ in
                syncWeekPage(to: selectedDay, animated: false)
            }
        }
    }

    // MARK: - Period + week chrome (one calm surface)

    private var historyChrome: some View {
        let weeks = periodWeeks
        let pageBinding = Binding<Int>(
            get: {
                guard !weeks.isEmpty else { return 0 }
                return min(max(0, selectedWeekIndex), weeks.count - 1)
            },
            set: { selectedWeekIndex = $0 }
        )

        return VStack(spacing: 14) {
            HStack(spacing: 4) {
                Button {
                    periodAnchor = HistoryPeriodHelper.shiftPayrollAnchor(periodAnchor, by: -1)
                    snapSelectedDayIntoPeriod()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                VStack(spacing: 2) {
                    Text(HistoryPeriodHelper.payrollPeriodTitle(for: activePeriod))
                        .font(.title3.weight(.semibold))
                    Text(HistoryPeriodHelper.shortRangeLabel(for: activePeriod))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                Button {
                    periodAnchor = HistoryPeriodHelper.shiftPayrollAnchor(periodAnchor, by: 1)
                    snapSelectedDayIntoPeriod()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            TabView(selection: pageBinding) {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    weekPage(week)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 68)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground))
    }

    private func weekPage(_ week: PayrollWeek) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                let letter = weekdayHeaderLetters.indices.contains(index)
                    ? weekdayHeaderLetters[index]
                    : ""
                dayCell(day, weekdayLetter: letter)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: PayrollWeekDay, weekdayLetter: String) -> some View {
        let isSelected = day.isInPeriod && calendar.isDate(day.date, inSameDayAs: selectedDay)
        let hasSession = day.isInPeriod && !sessionsForDay(day.date).isEmpty
        let isToday = calendar.isDateInToday(day.date)
        let number = dayNumberFormatter.string(from: day.date)

        return Button {
            guard day.isInPeriod else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDay = calendar.startOfDay(for: day.date)
            }
        } label: {
            VStack(spacing: 4) {
                Text(weekdayLetter)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(number)
                    .font(.body.weight(isSelected ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(dayNumberColor(
                        isSelected: isSelected,
                        isToday: isToday,
                        isInPeriod: day.isInPeriod
                    ))
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday && day.isInPeriod {
                            Circle().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.25)
                        }
                    }

                Circle()
                    .fill(hasSession && !isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .opacity(day.isInPeriod ? 1 : 0.28)
        }
        .buttonStyle(.plain)
        .disabled(!day.isInPeriod)
        .accessibilityLabel(dayAccessibilityLabel(day.date, hasSession: hasSession))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHidden(!day.isInPeriod)
    }

    private func dayNumberColor(isSelected: Bool, isToday: Bool, isInPeriod: Bool) -> Color {
        if !isInPeriod { return .secondary }
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }

    /// Shared insets so column headers and session rows stay locked together.
    private var historyTableInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
    }

    private func dayAccessibilityLabel(_ day: Date, hasSession: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        var label = formatter.string(from: day)
        if hasSession {
            label += ", " + L10n.historyDayHasShifts
        }
        return label
    }

    private func syncWeekPage(to day: Date, animated: Bool) {
        let weeks = periodWeeks
        guard let index = HistoryPeriodHelper.weekIndex(containing: day, in: weeks, calendar: calendar)
        else {
            selectedWeekIndex = 0
            return
        }
        guard selectedWeekIndex != index else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedWeekIndex = index
            }
        } else {
            selectedWeekIndex = index
        }
    }

    // MARK: - Table

    private var tableHeader: some View {
        historyColumns(
            date: L10n.historyColDate,
            clockIn: L10n.historyColIn,
            clockOut: L10n.historyColOut,
            hours: L10n.historyColHours,
            amount: L10n.historyColAmount,
            amountColor: .secondary,
            isHeader: true
        )
        .foregroundStyle(.secondary)
        .padding(.horizontal, historyTableInsets.leading)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
    }

    /// One shared column geometry for headers and data rows.
    private func historyColumns(
        date: String,
        clockIn: String,
        clockOut: String,
        hours: String,
        amount: String,
        amountColor: Color = .primary,
        isHeader: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            Text(date)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(clockIn)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(clockOut)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(hours)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(amount)
                .font(isHeader ? .caption2.weight(.semibold) : .caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(amountColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(isHeader ? .caption2.weight(.semibold) : .caption.monospacedDigit())
    }

    @ViewBuilder
    private var sessionsContent: some View {
        let rows = filteredSessions
        if rows.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                tableHeader

                List {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, session in
                        sessionRow(session, striped: index.isMultiple(of: 2))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSession = session
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    sessionPendingDelete = session
                                } label: {
                                    Label(L10n.editDelete, systemImage: "trash")
                                }

                                Button {
                                    exportSession(session)
                                } label: {
                                    Label(
                                        AppLocale.tr("history.exportShift"),
                                        systemImage: "square.and.arrow.up"
                                    )
                                }
                                .tint(.indigo)

                                Button {
                                    editingSession = session
                                } label: {
                                    Label(L10n.editTitle, systemImage: "pencil")
                                }
                                .tint(.blue)

                                Button {
                                    menuSession = session
                                } label: {
                                    Label(
                                        AppLocale.tr("history.more"),
                                        systemImage: "ellipsis"
                                    )
                                }
                                .tint(.gray)
                            }
                            .contextMenu {
                                Button {
                                    copySession(session)
                                } label: {
                                    Label(
                                        AppLocale.tr("history.copy"),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                                Button {
                                    editingSession = session
                                } label: {
                                    Label(L10n.editTitle, systemImage: "pencil")
                                }
                                Button {
                                    exportSession(session)
                                } label: {
                                    Label(
                                        AppLocale.tr("history.exportShift"),
                                        systemImage: "square.and.arrow.up"
                                    )
                                }
                                Button(role: .destructive) {
                                    sessionPendingDelete = session
                                } label: {
                                    Label(L10n.editDelete, systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }

    private func sessionRow(_ session: WorkSession, striped: Bool) -> some View {
        let breakdown = viewModel.breakdown(for: session)
        let amount = payMode == .net ? breakdown.netPay : breakdown.grossPay

        return historyColumns(
            date: shortDate(session.date),
            clockIn: timeFormatter.string(from: session.clockIn),
            clockOut: session.clockOut.map { timeFormatter.string(from: $0) } ?? "—",
            hours: HistoryPeriodHelper.formatHoursClock(breakdown.totalHours),
            amount: breakdown.formatted(amount),
            amountColor: payMode == .net ? .green : .primary
        )
        .padding(.horizontal, historyTableInsets.leading)
        .padding(.vertical, 11)
        .background {
            if striped {
                Color(.secondarySystemGroupedBackground).opacity(0.45)
            }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
        .contentShape(Rectangle())
        .textSelection(.enabled)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 28)
            Image(systemName: "hand.draw")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(AppLocale.tr("history.emptyPeriod"))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(AppLocale.tr("history.emptyPeriodHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sticky Summary

    private var stickySummaryBar: some View {
        let totals = periodTotals

        return VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L10n.historyTotalPay)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Picker("", selection: $payMode) {
                            ForEach(PayDisplayMode.allCases) { mode in
                                Text(mode == .net ? L10n.historyPayNet : L10n.historyPayGross).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }

                    Text(String(
                        format: AppLocale.tr("history.totalPayValue %@"),
                        payMode == .net ? totals.formattedNetPay : totals.formattedGrossPay
                    ))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(L10n.historyTotalHours)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(
                        format: AppLocale.tr("history.totalHoursValue %@"),
                        HistoryPeriodHelper.formatHoursClock(totals.totalHours)
                    ))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Data

    private var filteredSessions: [WorkSession] {
        viewModel.sortedSessions.filter {
            calendar.isDate($0.date, inSameDayAs: selectedDay)
        }
    }

    /// Totals for the full custom payroll window (not a calendar month).
    private var periodTotals: DayPayBreakdown {
        let period = activePeriod
        let sessions = viewModel.sortedSessions.filter { period.contains($0.date, calendar: calendar) }
        return OvertimeCalculator.aggregate(sessions: sessions, settings: viewModel.settings)
    }

    private func sessionsForDay(_ day: Date) -> [WorkSession] {
        viewModel.sessions.filter { calendar.isDate($0.date, inSameDayAs: day) && $0.clockOut != nil }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("dd/MM")
        return f.string(from: date)
    }

    private func alignToCurrentPayrollPeriod() {
        let period = HistoryPeriodHelper.payrollPeriod(
            containing: Date(),
            startDay: viewModel.settings.payrollStartDay,
            calendar: calendar
        )
        periodAnchor = period.labelMonth
        selectedDay = calendar.startOfDay(for: Date())
        if !period.contains(selectedDay, calendar: calendar) {
            selectedDay = period.start
        }
        syncWeekPage(to: selectedDay, animated: false)
    }

    private func snapSelectedDayIntoPeriod() {
        let period = activePeriod
        if !period.contains(selectedDay, calendar: calendar) {
            if period.contains(Date(), calendar: calendar) {
                selectedDay = calendar.startOfDay(for: Date())
            } else {
                selectedDay = period.start
            }
        }
        syncWeekPage(to: selectedDay, animated: false)
    }

    // MARK: - Row actions

    private func copySession(_ session: WorkSession) {
        let text = sessionCopyText(session)
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(60)
            ]
        )
        copyToastVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            copyToastVisible = false
        }
    }

    private func sessionCopyText(_ session: WorkSession) -> String {
        let breakdown = viewModel.breakdown(for: session)
        let amount = payMode == .net ? breakdown.netPay : breakdown.grossPay
        let out = session.clockOut.map { timeFormatter.string(from: $0) } ?? "—"
        return [
            shortDate(session.date),
            timeFormatter.string(from: session.clockIn),
            out,
            HistoryPeriodHelper.formatHoursClock(breakdown.totalHours),
            breakdown.formatted(amount)
        ].joined(separator: "  |  ")
    }

    private func exportSession(_ session: WorkSession) {
        let day = calendar.startOfDay(for: session.date)
        do {
            let url = try viewModel.export(
                range: .custom(from: day, to: day),
                format: .pdf,
                language: .phone
            )
            DispatchQueue.main.async {
                shareItem = ShareableFile(url: url)
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}
