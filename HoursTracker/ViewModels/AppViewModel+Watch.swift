import Foundation

extension AppViewModel {
    /// Precomputed state for the paired Watch app's whole UI — see
    /// `WatchConnectivityManager`. Uses the same `OvertimeCalculator`,
    /// `HistoryPeriodHelper`, and `WorkedDaysCounter` the phone's own tabs use, so the
    /// Watch shows real numbers (weekly OT cap, tax estimate, payroll period math)
    /// rather than a simplified re-derivation.
    ///
    /// - Parameter historyPeriodOffset: payroll periods away from the one containing
    ///   "now" (0 = current). The Watch's History tab pages through periods by asking
    ///   the phone to recompute at a new offset — see `WatchConnectivityManager`.
    func watchSnapshot(historyPeriodOffset: Int = 0) -> WatchSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let completedSessions = sessions.filter { $0.clockOut != nil }

        // MARK: Home

        let todaySessions = completedSessions.filter { calendar.isDate($0.date, inSameDayAs: today) }
        var todayHours = todaySessions.reduce(0) { $0 + $1.totalHours }
        if let active = activeSession, calendar.isDate(active.date, inSameDayAs: today) {
            todayHours += active.effectiveHours
        }
        let todayBreakdown = OvertimeCalculator.aggregate(sessions: todaySessions, settings: settings)

        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: today, end: today)
        let weekSessions = completedSessions.filter { weekInterval.contains($0.date) }
        let weekBreakdown = OvertimeCalculator.aggregate(sessions: weekSessions, settings: settings)
        var weekHours = weekBreakdown.totalHours
        if let active = activeSession, weekInterval.contains(active.date) {
            weekHours += active.effectiveHours
        }

        let monthSessions = completedSessions.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }
        let monthBreakdown = OvertimeCalculator.aggregate(sessions: monthSessions, settings: settings)
        let monthShiftCount = monthSessions.count

        let weekDailyHours = HistoryPeriodHelper.dailyHoursForWeek(
            containing: now, sessions: sessions, calendar: calendar
        )
        let weekDayLabels = (0..<7).map { offset -> String in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) else { return "" }
            return HistoryPeriodHelper.weekdayLetter(for: day)
        }
        let todayWeekdayIndex: Int? = (0..<7).first { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) else { return false }
            return calendar.isDate(day, inSameDayAs: today)
        }

        // MARK: History

        let currentPeriod = HistoryPeriodHelper.payrollPeriod(
            containing: now, startDay: settings.payrollStartDay, calendar: calendar
        )
        let historyAnchor = HistoryPeriodHelper.shiftPayrollAnchor(
            currentPeriod.labelMonth, by: historyPeriodOffset, calendar: calendar
        )
        let historyPeriod = HistoryPeriodHelper.payrollPeriod(
            forMonthAnchor: historyAnchor, startDay: settings.payrollStartDay, calendar: calendar
        )
        let historyPeriodSessions = sortedSessions.filter { historyPeriod.contains($0.date, calendar: calendar) }
        let historyTotals = OvertimeCalculator.aggregate(sessions: historyPeriodSessions, settings: settings)

        let historyDays: [WatchHistoryDay] = historyPeriod.days.map { day in
            let daySessions = historyPeriodSessions.filter { calendar.isDate($0.date, inSameDayAs: day) }
            guard !daySessions.isEmpty else {
                return WatchHistoryDay(date: day, isToday: calendar.isDateInToday(day), hasSession: false, netPay: nil, grossPay: nil)
            }
            let dayBreakdown = OvertimeCalculator.aggregate(sessions: daySessions, settings: settings)
            return WatchHistoryDay(
                date: day,
                isToday: calendar.isDateInToday(day),
                hasSession: true,
                netPay: dayBreakdown.netPay,
                grossPay: dayBreakdown.grossPay
            )
        }

        let historySessionEntries: [WatchHistorySession] = historyPeriodSessions.map { session in
            let sessionBreakdown = breakdown(for: session)
            return WatchHistorySession(
                id: session.id,
                date: session.date,
                clockIn: session.clockIn,
                clockOut: session.clockOut,
                hours: sessionBreakdown.totalHours,
                netPay: sessionBreakdown.netPay,
                grossPay: sessionBreakdown.grossPay
            )
        }

        let historyTrend = Self.monthlyTrend(sessions: sessions, settings: settings, calendar: calendar, now: now)

        // MARK: Export

        let exportThisMonth = Self.exportPreview(
            rangeLabel: HistoryPeriodHelper.shortRangeLabel(for: currentPeriod),
            sessions: completedSessions.filter { currentPeriod.contains($0.date, calendar: calendar) },
            settings: settings,
            calendar: calendar
        )
        let currentYear = calendar.component(.year, from: now)
        let exportThisYear = Self.exportPreview(
            rangeLabel: "\(currentYear)",
            sessions: completedSessions.filter { calendar.component(.year, from: $0.date) == currentYear },
            settings: settings,
            calendar: calendar
        )

        // MARK: Settings

        let settingsSummary = Self.settingsSummary(
            settings: settings,
            isCloudSyncSupported: isCloudSyncSupported,
            isCloudSyncEnabled: isICloudSyncEnabled,
            syncState: syncState,
            calendar: calendar
        )

        return WatchSnapshot(
            isClockedIn: isClockedIn,
            clockInTime: activeSession?.clockIn,
            todayHours: max(0, todayHours),
            todayNetPay: todayBreakdown.netPay,
            todayGrossPay: todayBreakdown.grossPay,
            weekHours: max(0, weekHours),
            weekNetPay: weekBreakdown.netPay,
            weekGrossPay: weekBreakdown.grossPay,
            monthShiftCount: monthShiftCount,
            monthNetPay: monthBreakdown.netPay,
            monthGrossPay: monthBreakdown.grossPay,
            weekDailyHours: weekDailyHours,
            weekDayLabels: weekDayLabels,
            todayWeekdayIndex: todayWeekdayIndex,
            homeStatOrder: HomeStatsLayout.shared.order.map(\.rawValue),
            historyPeriodOffset: historyPeriodOffset,
            historyPeriodTitle: HistoryPeriodHelper.payrollPeriodTitle(for: historyPeriod),
            historyPeriodRangeLabel: HistoryPeriodHelper.shortRangeLabel(for: historyPeriod),
            historyDays: historyDays,
            historySessions: historySessionEntries.sorted { $0.date > $1.date },
            historyTotalHours: historyTotals.totalHours,
            historyTotalNetPay: historyTotals.netPay,
            historyTotalGrossPay: historyTotals.grossPay,
            historyWorkedDayCount: WorkedDaysCounter.distinctWorkedDays(
                in: sessions, month: historyPeriod.labelMonth, calendar: calendar
            ),
            historyTrend: historyTrend,
            exportThisMonth: exportThisMonth,
            exportThisYear: exportThisYear,
            settingsSummary: settingsSummary,
            currencyCode: settings.currencyCode,
            workplaceName: settings.workplaceName,
            accentColorHex: HomeAccentTheme.shared.accent.hexString,
            generatedAt: now
        )
    }

    private static func monthlyTrend(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        calendar: Calendar,
        now: Date
    ) -> [WatchTrendPoint] {
        let formatter = Date.FormatStyle().month(.abbreviated)
        return (0..<6).reversed().compactMap { offset -> WatchTrendPoint? in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let interval = calendar.dateInterval(of: .month, for: monthStart)
            let monthSessions = sessions.filter { session in
                guard let interval else { return false }
                return session.clockOut != nil && session.clockIn >= interval.start && session.clockIn < interval.end
            }
            guard !monthSessions.isEmpty else {
                return WatchTrendPoint(id: monthStart, label: formatter.format(monthStart), hours: 0, pay: 0)
            }
            let hours = monthSessions.reduce(0) { $0 + $1.effectiveHours }
            let breakdown = OvertimeCalculator.aggregate(sessions: monthSessions, settings: settings)
            return WatchTrendPoint(id: monthStart, label: formatter.format(monthStart), hours: hours, pay: breakdown.totalPay)
        }
    }

    private static func exportPreview(
        rangeLabel: String,
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        calendar: Calendar
    ) -> WatchExportPreview {
        guard !sessions.isEmpty else {
            return WatchExportPreview(rangeLabel: rangeLabel, dayCount: 0, totalHours: 0, gross: 0, net: 0, hasData: false)
        }
        let breakdown = OvertimeCalculator.aggregate(sessions: sessions, settings: settings)
        let dayCount = Set(sessions.map { calendar.startOfDay(for: $0.date) }).count
        return WatchExportPreview(
            rangeLabel: rangeLabel,
            dayCount: dayCount,
            totalHours: breakdown.totalHours,
            gross: breakdown.totalPay,
            net: breakdown.netPay,
            hasData: true
        )
    }

    private static func settingsSummary(
        settings: WorkplaceSettings,
        isCloudSyncSupported: Bool,
        isCloudSyncEnabled: Bool,
        syncState: SyncState,
        calendar: Calendar
    ) -> WatchSettingsSummary {
        let weekdaySymbols = calendar.weekdaySymbols
        let restDayName = weekdaySymbols.indices.contains(settings.restDayWeekday - 1)
            ? weekdaySymbols[settings.restDayWeekday - 1]
            : ""
        let secondRestDayName: String? = settings.secondRestDayWeekday.flatMap { weekday in
            weekdaySymbols.indices.contains(weekday - 1) ? weekdaySymbols[weekday - 1] : nil
        }
        let payrollWindow = HistoryPeriodHelper.payrollPeriod(
            containing: Date(), startDay: settings.payrollStartDay, calendar: calendar
        )

        let syncStatusText: String
        switch syncState {
        case .idle:
            syncStatusText = "Synced"
        case .syncing:
            syncStatusText = "Syncing…"
        case .synced(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            syncStatusText = "Synced \(formatter.string(from: date))"
        case .failed:
            syncStatusText = "Sync failed"
        case .unavailable:
            syncStatusText = "iCloud unavailable"
        }

        let languageController = AppLanguageController.shared
        let languageOptions = AppLanguageOption.allCases.map {
            WatchLanguageOption(raw: $0.rawValue, label: $0.pickerLabel)
        }

        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        return WatchSettingsSummary(
            workerFullName: settings.workerFullName,
            workplaceName: settings.workplaceName,
            hourlyRate: settings.hourlyRate,
            currencyCode: settings.currencyCode,
            dailyGasAllowance: settings.dailyGasAllowance,
            standardDayHours: settings.standardDayHours,
            ot125HoursCap: settings.ot125HoursCap,
            weeklyStandardHours: settings.weeklyStandardHours,
            weeklyOvertimeCapHours: settings.weeklyOvertimeCapHours,
            restDayName: restDayName,
            secondRestDayName: secondRestDayName,
            payrollStartDay: settings.payrollStartDay,
            payrollWindowLabel: HistoryPeriodHelper.shortRangeLabel(for: payrollWindow),
            maritalStatusName: settings.maritalStatus.displayName,
            hasChildren: settings.hasChildren,
            numberOfChildren: settings.numberOfChildren,
            creditPoints: TaxCreditPointsCalculator.creditPoints(for: settings),
            appLockEnabled: UserDefaultsAppLockPreference.shared.isEnabled,
            hideWidgetPay: WidgetBridge.hidePay,
            isCloudSyncSupported: isCloudSyncSupported,
            isCloudSyncEnabled: isCloudSyncEnabled,
            cloudSyncStatusText: syncStatusText,
            languageOptionRaw: languageController.preference.rawValue,
            languageOptions: languageOptions,
            appVersion: "\(short) (\(build))"
        )
    }
}
