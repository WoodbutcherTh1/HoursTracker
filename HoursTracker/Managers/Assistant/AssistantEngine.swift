import Foundation

/// Turns an `AssistantPlan` into an `AssistantAnswer` using only the user's own data.
///
/// This is where the app's anti-hallucination guarantee actually lives. The model's
/// entire contribution is the plan — an action and a set of filters. Everything the user
/// reads is produced here: sessions come from `viewModel.sessions`, hours and money come
/// from `OvertimeCalculator`, documents come from `ExportManager`, payslips come from
/// `PayslipStore`, and the sentences around them are `L10n` templates. A model that
/// hallucinated a month with no data produces "no shifts found", never a made-up total.
///
/// Out-of-scope questions are refused by `resolve` from a fixed string, so the boundary
/// is structural rather than a prompt instruction someone could talk their way past.
struct AssistantEngine {
    let settings: WorkplaceSettings
    let sessions: [WorkSession]
    var calendar: Calendar = .current
    var now: Date = Date()
    var payslipStore: PayslipStore = .shared
    var exportManager: ExportManager = ExportManager()

    // MARK: - Entry point

    func resolve(plan: AssistantPlan) -> AssistantAnswer {
        switch plan.action {
        case .outOfScope:
            return .plain(L10n.assistantOutOfScope, note: L10n.assistantOutOfScopeHint)
        case .findPayslip:
            return findPayslip(period: plan.period ?? plan.filters.month)
        case .summarizeHours:
            return summarizeHours(plan: plan)
        case .aggregatePay:
            return aggregatePay(plan: plan)
        case .listSessions:
            return listSessions(plan: plan)
        case .listDaysWithoutSessions:
            return listDaysWithoutSessions(plan: plan)
        case .generateDocument:
            return generateDocument(plan: plan)
        }
    }

    // MARK: - Actions

    private func summarizeHours(plan: AssistantPlan) -> AssistantAnswer {
        let selection = select(with: plan.filters)
        guard !selection.sessions.isEmpty else { return emptyAnswer(scope: selection.description) }

        let totals = AssistantToolbox.aggregatePay(sessions: selection.sessions, settings: settings)
        let days = AssistantToolbox.distinctDays(in: selection.sessions, calendar: calendar).count

        return AssistantAnswer(
            headline: L10n.assistantHoursHeadline(
                HistoryPeriodHelper.formatHoursClock(totals.totalHours),
                days
            ),
            scope: selection.description,
            rows: [
                .init(label: L10n.summaryRegular, value: HistoryPeriodHelper.formatHoursClock(totals.regularHours)),
                .init(label: L10n.summaryOT125, value: HistoryPeriodHelper.formatHoursClock(totals.ot125Hours)),
                .init(label: L10n.summaryOT150, value: HistoryPeriodHelper.formatHoursClock(totals.ot150Hours))
            ]
        )
    }

    private func aggregatePay(plan: AssistantPlan) -> AssistantAnswer {
        let selection = select(with: plan.filters)
        guard !selection.sessions.isEmpty else { return emptyAnswer(scope: selection.description) }

        let totals = AssistantToolbox.aggregatePay(sessions: selection.sessions, settings: settings)
        let mode = plan.payMode ?? .net

        return AssistantAnswer(
            headline: mode == .net
                ? L10n.assistantPayNetHeadline(totals.formattedNetPay)
                : L10n.assistantPayGrossHeadline(totals.formattedGrossPay),
            scope: selection.description,
            rows: [
                .init(label: L10n.historyPayGross, value: totals.formattedGrossPay),
                .init(label: L10n.historyPayNet, value: totals.formattedNetPay),
                .init(label: L10n.historyTotalHours, value: HistoryPeriodHelper.formatHoursClock(totals.totalHours))
            ],
            note: L10n.assistantPayEstimateNote
        )
    }

    private func listSessions(plan: AssistantPlan) -> AssistantAnswer {
        let selection = select(with: plan.filters)
        guard !selection.sessions.isEmpty else { return emptyAnswer(scope: selection.description) }

        let ordered = selection.sessions.sorted { $0.clockIn < $1.clockIn }
        let shown = ordered.prefix(Self.maxListedRows)
        let rows = shown.map { session -> AssistantAnswer.Row in
            let breakdown = OvertimeCalculator.breakdown(
                for: session,
                in: sessions,
                settings: settings,
                calendar: calendar
            )
            return .init(
                label: dayLabel(session.date),
                value: HistoryPeriodHelper.formatHoursClock(breakdown.totalHours)
            )
        }

        return AssistantAnswer(
            headline: L10n.assistantShiftsHeadline(ordered.count),
            scope: selection.description,
            rows: rows,
            note: ordered.count > shown.count
                ? L10n.assistantMoreRows(ordered.count - shown.count)
                : nil
        )
    }

    private func listDaysWithoutSessions(plan: AssistantPlan) -> AssistantAnswer {
        let month = resolvedMonth(from: plan.filters) ?? now
        let days = AssistantToolbox.findDaysWithoutSessions(
            month: month,
            sessions: sessions,
            now: now,
            calendar: calendar
        )
        let monthName = HistoryPeriodHelper.monthTitle(for: month)

        guard !days.isEmpty else {
            return AssistantAnswer(
                headline: L10n.assistantNoDaysOff,
                scope: monthName
            )
        }

        let shown = days.prefix(Self.maxListedRows)
        return AssistantAnswer(
            headline: L10n.assistantDaysOffHeadline(days.count),
            scope: monthName,
            rows: shown.map { .init(label: dayLabel($0), value: weekdayLabel($0)) },
            note: days.count > shown.count ? L10n.assistantMoreRows(days.count - shown.count) : nil
        )
    }

    private func generateDocument(plan: AssistantPlan) -> AssistantAnswer {
        let selection = select(with: plan.filters)
        guard !selection.sessions.isEmpty else { return emptyAnswer(scope: selection.description) }

        let format = (plan.documentFormat ?? .pdf).exportFormat
        // The already-filtered sessions are handed to the exporter, with the range set to
        // the span they actually cover. `buildReport` re-filters by that span, which is a
        // no-op for this set, but it gives the report an accurate date-range header —
        // and it keeps document generation on the app's one export path rather than a
        // second implementation that could format money differently.
        let days = AssistantToolbox.distinctDays(in: selection.sessions, calendar: calendar)
        guard let first = days.first, let last = days.last else {
            return emptyAnswer(scope: selection.description)
        }

        let report = exportManager.buildReport(
            sessions: selection.sessions,
            settings: settings,
            range: .custom(from: first, to: last)
        )
        do {
            let url = try exportManager.export(report: report, format: format)
            return AssistantAnswer(
                headline: L10n.assistantDocumentReady,
                scope: selection.description,
                rows: [
                    .init(label: L10n.historyTotalHours,
                          value: HistoryPeriodHelper.formatHoursClock(report.totals.totalHours)),
                    .init(label: L10n.historyPayNet, value: report.totals.formattedNetPay)
                ],
                attachment: .document(url: url, fileName: url.lastPathComponent)
            )
        } catch {
            return .plain(L10n.assistantDocumentFailed)
        }
    }

    /// Retrieval only. If `PayslipStore` has nothing for the period, that is the answer —
    /// there is no path here that produces payslip figures the user never uploaded.
    private func findPayslip(period: String?) -> AssistantAnswer {
        let month = period.flatMap(Self.parseMonth) ?? now
        let monthName = HistoryPeriodHelper.monthTitle(for: month)

        let records = (try? payslipStore.listPayslips()) ?? []
        let match = records.first { record in
            calendar.isDate(record.effectivePeriodMonth, equalTo: month, toGranularity: .month)
        }

        guard let match else {
            return AssistantAnswer(
                headline: L10n.assistantPayslipMissing(monthName),
                scope: monthName,
                note: L10n.assistantPayslipMissingHint
            )
        }

        var rows: [AssistantAnswer.Row] = []
        if let gross = match.effectiveGrossPay {
            rows.append(.init(label: L10n.payslipGross, value: formatDecimal(gross, record: match)))
        }
        if let net = match.effectiveNetPay {
            rows.append(.init(label: L10n.payslipNet, value: formatDecimal(net, record: match)))
        }

        return AssistantAnswer(
            headline: L10n.assistantPayslipFound(monthName),
            scope: match.periodLabel ?? monthName,
            rows: rows,
            attachment: .payslip(record: match, fileURL: payslipStore.url(for: match))
        )
    }

    // MARK: - Filtering

    /// A filtered set of sessions plus a human description of what was actually counted.
    struct Selection {
        let sessions: [WorkSession]
        let description: String
    }

    /// Applies the plan's filters in sequence — each one a `AssistantToolbox` function —
    /// and builds the scope line as it goes, so the answer can always say what it looked
    /// at. Only completed shifts are ever considered: a running shift has no final hours.
    func select(with filters: AssistantFilters) -> Selection {
        var result = sessions.filter { $0.clockOut != nil }
        var parts: [String] = []

        if let interval = resolvedInterval(from: filters) {
            result = AssistantToolbox.filterSessionsByDateRange(
                result,
                start: interval.start,
                end: interval.end,
                calendar: calendar
            )
            parts.append(rangeLabel(from: interval.start, to: interval.end))
        } else {
            parts.append(L10n.assistantScopeAllTime)
        }

        if let text = filters.clockInAfter, let minutes = AssistantToolbox.parseTimeOfDay(text) {
            result = AssistantToolbox.filterSessionsByClockInAfter(
                result,
                minutesFromMidnight: minutes,
                calendar: calendar
            )
            parts.append(L10n.assistantScopeAfter(text))
        }

        if let text = filters.clockInBefore, let minutes = AssistantToolbox.parseTimeOfDay(text) {
            result = AssistantToolbox.filterSessionsByClockInBefore(
                result,
                minutesFromMidnight: minutes,
                calendar: calendar
            )
            parts.append(L10n.assistantScopeBefore(text))
        }

        if let tier = filters.overtimeTier {
            result = AssistantToolbox.filterSessionsByOvertimeTier(
                result,
                tier: tier,
                settings: settings,
                calendar: calendar
            )
            parts.append(tierLabel(tier))
        }

        if let raw = filters.dayType, let dayType = DayType(rawValue: raw) {
            result = AssistantToolbox.filterSessionsByDayType(result, dayType: dayType)
            parts.append(dayType.localizedName)
        }

        return Selection(sessions: result, description: parts.joined(separator: " · "))
    }

    // MARK: - Date resolution

    /// The date window a set of filters describes, or nil for "everything on record".
    func resolvedInterval(from filters: AssistantFilters) -> DateInterval? {
        if let start = filters.startDate.flatMap(Self.parseDay),
           let end = filters.endDate.flatMap(Self.parseDay) {
            return DateInterval(start: min(start, end), end: max(start, end))
        }
        if let month = resolvedMonth(from: filters) {
            let days = HistoryPeriodHelper.daysInMonth(containing: month, calendar: calendar)
            if let first = days.first, let last = days.last {
                return DateInterval(start: first, end: last)
            }
        }
        // A single open-ended bound still narrows things usefully: "since March 1st".
        if let start = filters.startDate.flatMap(Self.parseDay) {
            return DateInterval(start: start, end: max(start, now))
        }
        if let end = filters.endDate.flatMap(Self.parseDay) {
            let earliest = sessions.map(\.date).min() ?? end
            return DateInterval(start: min(earliest, end), end: end)
        }
        return nil
    }

    func resolvedMonth(from filters: AssistantFilters) -> Date? {
        filters.month.flatMap(Self.parseMonth)
    }

    /// `"YYYY-MM-DD"` in the Gregorian calendar. Nil for anything else — a bad date is
    /// dropped rather than guessed at.
    static func parseDay(_ text: String) -> Date? {
        Self.dayFormatter.date(from: text)
    }

    /// `"YYYY-MM"`, tolerating a full date since models sometimes send one.
    static func parseMonth(_ text: String) -> Date? {
        if let month = Self.monthFormatter.date(from: text) { return month }
        return parseDay(text)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    // MARK: - Formatting

    private static let maxListedRows = 12

    private func emptyAnswer(scope: String) -> AssistantAnswer {
        AssistantAnswer(
            headline: L10n.assistantNoData,
            scope: scope,
            note: L10n.assistantNoDataHint
        )
    }

    private func dayLabel(_ date: Date) -> String {
        AppLocale.makeDateFormatter(template: "dd/MM").string(from: date)
    }

    private func weekdayLabel(_ date: Date) -> String {
        AppLocale.makeDateFormatter(template: "EEE").string(from: date)
    }

    private func rangeLabel(from start: Date, to end: Date) -> String {
        calendar.isDate(start, inSameDayAs: end)
            ? dayLabel(start)
            : "\(dayLabel(start)) – \(dayLabel(end))"
    }

    private func tierLabel(_ tier: AssistantOvertimeTier) -> String {
        switch tier {
        case .regular: return L10n.summaryRegular
        case .ot125: return L10n.summaryOT125
        case .ot150: return L10n.summaryOT150
        }
    }

    private func formatDecimal(_ amount: Decimal, record: PayslipRecord) -> String {
        let code = record.userOverrides?.currencyCode
            ?? record.extraction.currencyCode
            ?? settings.currencyCode
        return PayFormatter.string(NSDecimalNumber(decimal: amount).doubleValue, currencyCode: code)
    }
}
