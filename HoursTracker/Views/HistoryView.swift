import SwiftUI
import UIKit

struct HistoryView: View {
    @ObservedObject var viewModel: AppViewModel

    /// Anchor month for the payroll cycle label / chevron navigation.
    @State private var periodAnchor: Date = Date()
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var payMode: PayDisplayMode = .net
    @State private var selectedSession: WorkSession?
    @State private var editingSession: WorkSession?
    @State private var sessionPendingDelete: WorkSession?
    @State private var menuSession: WorkSession?
    @State private var showScanner = false
    @State private var showManualEntry = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                periodHeader
                daySelector
                tableHeader
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
            .sheet(isPresented: $showShareSheet) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
            .confirmationDialog(
                L10n.editDeleteConfirm,
                isPresented: Binding(
                    get: { sessionPendingDelete != nil },
                    set: { if !$0 { sessionPendingDelete = nil } }
                ),
                titleVisibility: .visible
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
                String(localized: "history.rowMenu", defaultValue: "Shift options"),
                isPresented: Binding(
                    get: { menuSession != nil },
                    set: { if !$0 { menuSession = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let session = menuSession {
                    Button(String(localized: "history.copy", defaultValue: "Copy")) {
                        copySession(session)
                        menuSession = nil
                    }
                    Button(L10n.editTitle) {
                        editingSession = session
                        menuSession = nil
                    }
                    Button(String(localized: "history.exportShift", defaultValue: "Export")) {
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
                    Text(String(localized: "history.copied", defaultValue: "Copied"))
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
        }
    }

    // MARK: - Header

    private var periodHeader: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    periodAnchor = HistoryPeriodHelper.shiftPayrollAnchor(periodAnchor, by: -1)
                    snapSelectedDayIntoPeriod()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(HistoryPeriodHelper.payrollPeriodTitle(for: activePeriod))
                        .font(.headline)
                    Text(HistoryPeriodHelper.shortRangeLabel(for: activePeriod))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    periodAnchor = HistoryPeriodHelper.shiftPayrollAnchor(periodAnchor, by: 1)
                    snapSelectedDayIntoPeriod()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
    }

    // MARK: - Day Selector

    private var daySelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(activePeriod.days, id: \.self) { day in
                        dayChip(day)
                            .id(day)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onAppear {
                proxy.scrollTo(selectedDay, anchor: .center)
            }
            .onChange(of: selectedDay) { _, newDay in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(newDay, anchor: .center)
                }
            }
            .onChange(of: periodAnchor) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo(selectedDay, anchor: .center)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func dayChip(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let hasSession = !sessionsForDay(day).isEmpty
        let isToday = calendar.isDateInToday(day)

        return Button {
            selectedDay = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text(HistoryPeriodHelper.weekdayLetter(for: day))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(dayNumberFormatter.string(from: day))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)

                Circle()
                    .fill(hasSession ? Color.accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 40, height: 58)
            .background(
                Circle()
                    .fill(isSelected ? Color(.systemBackground) : Color.clear)
                    .shadow(color: isSelected ? .black.opacity(0.14) : .clear, radius: 5, y: 2)
                    .frame(width: 42, height: 42)
                    .offset(y: 2)
            )
            .overlay {
                if isToday && !isSelected {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.2)
                        .frame(width: 42, height: 42)
                        .offset(y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Table

    private var tableHeader: some View {
        HStack(spacing: 0) {
            headerCell(L10n.historyColDate)
            headerCell(L10n.historyColIn)
            headerCell(L10n.historyColOut)
            headerCell(L10n.historyColHours)
            headerCell(L10n.historyColAmount, alignEnd: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill))
    }

    private func headerCell(_ title: String, alignEnd: Bool = false) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: alignEnd ? .trailing : .leading)
    }

    @ViewBuilder
    private var sessionsContent: some View {
        let rows = filteredSessions
        if rows.isEmpty {
            emptyState
        } else {
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
                                    String(localized: "history.exportShift", defaultValue: "Export"),
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
                                    String(localized: "history.more", defaultValue: "More"),
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
                                    String(localized: "history.copy", defaultValue: "Copy"),
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
                                    String(localized: "history.exportShift", defaultValue: "Export"),
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
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func sessionRow(_ session: WorkSession, striped: Bool) -> some View {
        let breakdown = viewModel.breakdown(for: session)
        let amount = payMode == .net ? breakdown.netPay : breakdown.grossPay

        return HStack(spacing: 0) {
            Text(shortDate(session.date))
                .font(.caption.weight(.medium).monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeFormatter.string(from: session.clockIn))
                .font(.caption.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(session.clockOut.map { timeFormatter.string(from: $0) } ?? "—")
                .font(.caption.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(HistoryPeriodHelper.formatHoursClock(breakdown.totalHours))
                .font(.caption.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(breakdown.formatted(amount))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(payMode == .net ? Color.green : Color.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(striped ? Color(.secondarySystemGroupedBackground).opacity(0.55) : Color(.systemBackground))
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
            Text(String(localized: "history.emptyPeriod", defaultValue: "אין משמרות לתקופה שנבחרה"))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(String(localized: "history.emptyPeriodHint", defaultValue: "Swipe the days above or add a shift."))
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
                        format: String(localized: "history.totalPayValue %@"),
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
                        format: String(localized: "history.totalHoursValue %@"),
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
    }

    // MARK: - Row actions

    private func copySession(_ session: WorkSession) {
        UIPasteboard.general.string = sessionCopyText(session)
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
            shareURL = url
            showShareSheet = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}
