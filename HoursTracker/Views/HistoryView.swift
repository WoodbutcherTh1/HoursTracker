import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HistoryView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    /// Anchor month for the payroll cycle label / chevron navigation.
    @State private var periodAnchor: Date = Date()
    /// `nil` = show all sessions in the active payroll period (default on open).
    /// Non-nil = filter to that calendar day only.
    @State private var selectedDay: Date? = nil
    /// Page index into `periodWeeks` for the Health-style week strip.
    @State private var selectedWeekIndex: Int = 0
    /// Skyscanner-style expand: swipe the week strip down to see every week in the
    /// period at once (with each day's pay total), swipe up to collapse back.
    @State private var isCalendarExpanded: Bool = false
    @AppStorage("historyPayDisplayMode") private var payMode: PayDisplayMode = .net
    @State private var selectedSession: WorkSession?
    @State private var editingSession: WorkSession?
    @State private var sessionPendingDelete: WorkSession?
    @State private var menuSession: WorkSession?
    @State private var showScanner = false
    @State private var showManualEntry = false
    @State private var shareItem: ShareableFile?
    @State private var exportError: String?
    @State private var copyToastVisible = false
    @State private var showPayBreakdown = false

    private let calendar = Calendar.current

    private var timeFormatter: DateFormatter {
        AppLocale.makeDateFormatter(timeStyle: .short)
    }

    private var dayNumberFormatter: DateFormatter {
        let f = AppLocale.makeDateFormatter()
        f.dateFormat = "d"
        return f
    }

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
                if selectedDay == nil && !filteredSessions.isEmpty {
                    // Six-month trend: hours per month + average monthly pay.
                    // Hidden once a specific day is picked so that day's own
                    // shift rows (below) land right under the calendar instead
                    // of being pushed off-screen by the trend chart — this
                    // matters most when the full calendar is expanded.
                    MonthlyTrendCard(viewModel: viewModel)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                sessionsContent
                stickySummaryBar
            }
            .background(appBackground.background.ignoresSafeArea())
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
                    AssistantToolbarButton(onOpen: { viewModel.showAssistant = true })
                }
            }
            .toolbarBackground(appBackground.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            .sheet(isPresented: $showPayBreakdown) {
                HistoryPayBreakdownSheet(
                    breakdown: periodTotals,
                    workedDayCount: workedDayCount,
                    showsPendingWorkedDay: hasPendingWorkedDay
                )
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
                if let newDay {
                    syncWeekPage(to: newDay, animated: true)
                }
            }
            .onChange(of: periodAnchor) { _, _ in
                if let day = selectedDay {
                    syncWeekPage(to: day, animated: false)
                } else {
                    syncWeekPage(to: Date(), animated: false)
                }
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

            VStack(spacing: 6) {
                if isCalendarExpanded {
                    expandedCalendarGrid
                } else {
                    TabView(selection: pageBinding) {
                        ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                            weekPage(week)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 68)
                }

                calendarToggleHint
            }
            .simultaneousGesture(calendarDragGesture)

            if selectedDay != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDay = nil
                    }
                } label: {
                    Label(L10n.historyShowAllDays, systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityIdentifier("phone.history.showAllDays")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(appBackground.background)
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
        let isSelected = day.isInPeriod
            && selectedDay.map { calendar.isDate(day.date, inSameDayAs: $0) } == true
        let hasSession = day.isInPeriod && !sessionsForDay(day.date).isEmpty
        let isToday = calendar.isDateInToday(day.date)
        let number = dayNumberFormatter.string(from: day.date)

        return Button {
            guard day.isInPeriod else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                let tapped = calendar.startOfDay(for: day.date)
                // Tap again to clear day filter → full period list.
                if let current = selectedDay, calendar.isDate(current, inSameDayAs: tapped) {
                    selectedDay = nil
                } else {
                    selectedDay = tapped
                }
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

    // MARK: - Expanded calendar (Skyscanner-style swipe-down)

    private var calendarToggleHint: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isCalendarExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(isCalendarExpanded ? L10n.historyCollapseCalendarHint : L10n.historyExpandCalendarHint)
                    .font(.caption2.weight(.medium))
                Image(systemName: isCalendarExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("phone.history.calendarToggleHint")
    }

    /// A vertical swipe on the strip/grid area toggles expanded state. A horizontal
    /// swipe moves to the previous/next payroll period — but only once it's clearly
    /// wider than a normal week-to-week page swipe on the collapsed strip's own
    /// TabView, so the two don't fight each other (both gestures see the same touch;
    /// this one only acts past that width).
    private var calendarDragGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                let translation = value.translation
                if abs(translation.height) > abs(translation.width) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if translation.height > 24 {
                            isCalendarExpanded = true
                        } else if translation.height < -24 {
                            isCalendarExpanded = false
                        }
                    }
                } else if abs(translation.width) > 100 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        periodAnchor = HistoryPeriodHelper.shiftPayrollAnchor(periodAnchor, by: translation.width < 0 ? 1 : -1)
                    }
                    snapSelectedDayIntoPeriod()
                }
            }
    }

    /// Every week of the active payroll period, stacked, with each day's pay total
    /// underneath its number — the "full calendar" swiped down into.
    private var expandedCalendarGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(weekdayHeaderLetters.indices, id: \.self) { index in
                    Text(weekdayHeaderLetters[index])
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(periodWeeks) { week in
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        calendarDayCell(day)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func calendarDayCell(_ day: PayrollWeekDay) -> some View {
        let isSelected = day.isInPeriod
            && selectedDay.map { calendar.isDate(day.date, inSameDayAs: $0) } == true
        let isToday = calendar.isDateInToday(day.date)
        let number = dayNumberFormatter.string(from: day.date)
        let amount = day.isInPeriod ? dailyPayTotal(for: day.date) : nil

        return Button {
            guard day.isInPeriod else { return }
            let tapped = calendar.startOfDay(for: day.date)
            withAnimation(.easeInOut(duration: 0.2)) {
                // Tap again to clear day filter → full period list.
                if let current = selectedDay, calendar.isDate(current, inSameDayAs: tapped) {
                    selectedDay = nil
                } else {
                    selectedDay = tapped
                }
            }
            // So the week strip lands on the right page once the user swipes back up.
            syncWeekPage(to: tapped, animated: false)
        } label: {
            VStack(spacing: 3) {
                Text(number)
                    .font(.subheadline.weight(isSelected ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(dayNumberColor(
                        isSelected: isSelected,
                        isToday: isToday,
                        isInPeriod: day.isInPeriod
                    ))
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday && day.isInPeriod {
                            Circle().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.25)
                        }
                    }

                // Blank (not a placeholder dash) for days without a completed shift,
                // same as the week strip's plain dot today.
                Text(amount.map(formattedDailyAmount) ?? " ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .opacity(day.isInPeriod ? 1 : 0.28)
        }
        .buttonStyle(.plain)
        .disabled(!day.isInPeriod)
        .accessibilityLabel(dayAccessibilityLabel(day.date, hasSession: amount != nil))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHidden(!day.isInPeriod)
    }

    /// Sum of this day's session pay (net or gross per the existing `payMode` toggle),
    /// `nil` when nothing was worked so the cell renders blank.
    private func dailyPayTotal(for day: Date) -> Double? {
        let sessions = sessionsForDay(day)
        guard !sessions.isEmpty else { return nil }
        return sessions.reduce(0.0) { partial, session in
            let breakdown = viewModel.breakdown(for: session)
            return partial + (payMode == .net ? breakdown.netPay : breakdown.grossPay)
        }
    }

    private func formattedDailyAmount(_ amount: Double) -> String {
        PayFormatter.string(amount, currencyCode: viewModel.settings.currencyCode)
    }

    /// Shared insets so column headers and session rows stay locked together.
    private var historyTableInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
    }

    private func dayAccessibilityLabel(_ day: Date, hasSession: Bool) -> String {
        let formatter = AppLocale.makeDateFormatter(dateStyle: .full)
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
            // Hairline edge so the table stays defined against any chosen background,
            // including pure-black Onyx where it would otherwise merge into the page.
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
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
            if selectedDay != nil {
                Text(L10n.historyEmptyPeriod)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(L10n.historyEmptyPeriodHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button(L10n.historyShowAllDays) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDay = nil
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
            } else {
                Text(L10n.historyEmpty)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(L10n.historyEmptyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
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

                        Button {
                            showPayBreakdown = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                        }
                        .accessibilityLabel(L10n.historyPayBreakdownButton)

                        // A compact accessory at the same visual weight as the info
                        // button beside it — not a third stat column. It used to be a
                        // full peer of the pay/hours blocks below, which is what made
                        // this bar taller and busier than before; folded back into the
                        // control row, the bar is exactly the size it always was.
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            WorkedDaysBadge(
                                dayCount: workedDayCount,
                                showsPendingDay: hasPendingWorkedDay,
                                valueFont: .caption.weight(.semibold).monospacedDigit(),
                                showsTitle: false
                            )
                        }
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(String(
                        format: AppLocale.tr("history.totalHoursValue %@"),
                        HistoryPeriodHelper.formatHoursClock(totals.totalHours)
                    ))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Data

    private var filteredSessions: [WorkSession] {
        let period = activePeriod
        if let selectedDay {
            return viewModel.sortedSessions.filter {
                calendar.isDate($0.date, inSameDayAs: selectedDay)
            }
        }
        return viewModel.sortedSessions.filter {
            period.contains($0.date, calendar: calendar)
        }
    }

    /// Distinct calendar days worked — not the number of shifts. Two clock-in/out pairs
    /// on one day are one day here, which is what "days worked" means to a reader (and
    /// is why Home's session-counting `monthShiftCount` is deliberately not reused).
    ///
    /// Anchored to the calendar month the displayed payroll period is labeled with, so
    /// paging back to June shows June's days rather than this month's. In the default
    /// state — History opens on the current period — that is the current calendar month.
    private var workedDayCount: Int {
        WorkedDaysCounter.distinctWorkedDays(
            in: viewModel.sessions,
            month: activePeriod.labelMonth,
            calendar: calendar
        )
    }

    /// Drives the green "+1?" bubble: a shift is running, and its day has no completed
    /// session yet, so clocking out will genuinely add a day. Clocking in a second time
    /// on a day already worked shows nothing — that day is counted either way.
    private var hasPendingWorkedDay: Bool {
        WorkedDaysCounter.openShiftWouldAddADay(
            activeSession: viewModel.activeSession,
            sessions: viewModel.sessions,
            month: activePeriod.labelMonth,
            calendar: calendar
        )
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
        AppLocale.makeDateFormatter(template: "dd/MM").string(from: date)
    }

    private func alignToCurrentPayrollPeriod() {
        let period = HistoryPeriodHelper.payrollPeriod(
            containing: Date(),
            startDay: viewModel.settings.payrollStartDay,
            calendar: calendar
        )
        periodAnchor = period.labelMonth
        // Default: no day selected → full period list (not “empty today”).
        selectedDay = nil
        syncWeekPage(to: Date(), animated: false)
    }

    private func snapSelectedDayIntoPeriod() {
        let period = activePeriod
        if let day = selectedDay, !period.contains(day, calendar: calendar) {
            selectedDay = nil
        }
        syncWeekPage(to: selectedDay ?? Date(), animated: false)
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
