import Foundation

struct DayPayBreakdown: Equatable {
    /// Base-rate hours: 100% on regular days, 150% on rest days / holidays.
    let regularHours: Double
    /// First overtime tier: 125% on regular days, 175% on rest days / holidays.
    let ot125Hours: Double
    /// Second overtime tier: 150% on regular days, 200% on rest days / holidays.
    let ot150Hours: Double
    let totalHours: Double
    let gasAllowance: Double
    let basePay: Double
    let ot125Pay: Double
    let ot150Pay: Double
    /// Gross pay (ברוטו) including gas allowance.
    let totalPay: Double
    /// Estimated net pay (נטו).
    let netPay: Double
    let incomeTax: Double
    let nationalInsurance: Double
    let healthTax: Double
    let creditPointsApplied: Double
    let creditPoints: Double
    let currencyCode: String

    var grossPay: Double { totalPay }

    func formatted(_ amount: Double) -> String {
        PayFormatter.string(amount, currencyCode: currencyCode)
    }

    var formattedTotalPay: String { formatted(totalPay) }

    var formattedGrossPay: String { formatted(grossPay) }

    var formattedNetPay: String { formatted(netPay) }
}

enum OvertimeCalculator {
    struct RateTiers: Equatable {
        let base: Double
        let tier1: Double
        let tier2: Double
    }

    static func tiers(for dayType: DayType) -> RateTiers {
        switch dayType {
        case .regular:
            return RateTiers(base: 1.0, tier1: 1.25, tier2: 1.5)
        case .restDay, .holiday:
            // Rest-day / holiday work pays 150% from the first hour;
            // overtime tiers add the same +25% / +50% on top.
            return RateTiers(base: 1.5, tier1: 1.75, tier2: 2.0)
        case .sick:
            // Sick days never have worked hours, so this is never actually
            // consulted — `breakdowns(forDay:)` prices sick sessions itself.
            return RateTiers(base: 0, tier1: 0, tier2: 0)
        }
    }

    /// 1-indexed position within a run of consecutive *calendar* days all
    /// marked `.sick`. A gap of any kind — including the weekly rest day —
    /// resets the run; only calendar-adjacent sick-marked days extend it.
    static func sickStreakDayNumber(
        for date: Date,
        sickDates: Set<Date>,
        calendar: Calendar = .current
    ) -> Int {
        var count = 1
        var cursor = calendar.startOfDay(for: date)
        while let previous = calendar.date(byAdding: .day, value: -1, to: cursor),
              sickDates.contains(calendar.startOfDay(for: previous)) {
            count += 1
            cursor = previous
        }
        return count
    }

    /// Israeli sick-pay schedule: day 1 unpaid, days 2–3 half pay, day 4+ full pay.
    static func sickPayPercentage(streakDayNumber: Int) -> Double {
        switch streakDayNumber {
        case ...1: return 0.0
        case 2, 3: return 0.5
        default: return 1.0
        }
    }

    /// Streak position for every `.sick`-marked calendar day found in `sessions`.
    static func sickStreakDayNumbers(
        sessions: [WorkSession],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        let sickDates = Set(
            sessions.filter { $0.dayType == .sick }.map { calendar.startOfDay(for: $0.date) }
        )
        var result: [Date: Int] = [:]
        for date in sickDates {
            result[date] = sickStreakDayNumber(for: date, sickDates: sickDates, calendar: calendar)
        }
        return result
    }

    static func standardHours(for session: WorkSession, settings: WorkplaceSettings) -> Double {
        session.isNightShift ? settings.nightStandardDayHours : settings.standardDayHours
    }

    /// Simple regular-day breakdown from a raw hours total. Kept for callers
    /// that have no session context (previews, quick estimates, older tests).
    static func breakdown(
        totalHours: Double,
        settings: WorkplaceSettings,
        includeGasAllowance: Bool = true
    ) -> DayPayBreakdown {
        let regular = min(totalHours, settings.standardDayHours)
        let overtimeTotal = max(0, totalHours - settings.standardDayHours)
        let ot125 = min(overtimeTotal, settings.ot125HoursCap)
        let ot150 = max(0, overtimeTotal - ot125)

        let rate = settings.hourlyRate
        let gas = includeGasAllowance ? settings.dailyGasAllowance : 0
        let basePay = regular * rate
        let ot125Pay = ot125 * rate * 1.25
        let ot150Pay = ot150 * rate * 1.5
        let gross = basePay + ot125Pay + ot150Pay + gas

        let tax = IsraeliTaxEstimator.estimateDailyNet(fromDailyGross: gross, settings: settings)
        let points = TaxCreditPointsCalculator.creditPoints(for: settings)

        return DayPayBreakdown(
            regularHours: regular,
            ot125Hours: ot125,
            ot150Hours: ot150,
            totalHours: totalHours,
            gasAllowance: gas,
            basePay: basePay,
            ot125Pay: ot125Pay,
            ot150Pay: ot150Pay,
            totalPay: gross,
            netPay: tax.net,
            incomeTax: tax.incomeTax,
            nationalInsurance: tax.nationalInsurance,
            healthTax: tax.healthTax,
            creditPointsApplied: tax.creditApplied,
            creditPoints: points,
            currencyCode: settings.currencyCode
        )
    }

    /// Day-aware breakdowns for the sessions of ONE calendar day.
    /// Sessions are processed in clock-in order and share a single daily tier
    /// allowance, so a second shift on the same day continues where the first
    /// stopped instead of restarting the standard-hours counter. The daily gas
    /// allowance is paid once, on the day's first session. Per-session values
    /// sum exactly to the day's totals.
    static func breakdowns(
        forDay daySessions: [WorkSession],
        settings: WorkplaceSettings,
        sickStreakDayNumbers: [Date: Int] = [:],
        calendar: Calendar = .current
    ) -> [(session: WorkSession, breakdown: DayPayBreakdown)] {
        guard !daySessions.isEmpty else { return [] }

        struct Slice {
            let session: WorkSession
            let base: Double
            let tier1: Double
            let tier2: Double
            let hours: Double
            let gas: Double
            let basePay: Double
            let tier1Pay: Double
            let tier2Pay: Double
            let gross: Double
        }

        let ordered = daySessions.sorted { $0.clockIn < $1.clockIn }
        let rate = settings.hourlyRate
        var consumed = 0.0
        var gasRemaining = settings.dailyGasAllowance
        var slices: [Slice] = []

        for session in ordered {
            let isSick = session.dayType == .sick
            let hours = isSick ? 0 : session.effectiveHours
            let standard = standardHours(for: session, settings: settings)
            let tier1Boundary = standard
            let tier2Boundary = standard + settings.ot125HoursCap

            let start = consumed
            let end = start + hours
            let base = max(0, min(end, tier1Boundary) - start)
            let tier1 = max(0, min(end, tier2Boundary) - max(start, tier1Boundary))
            let tier2 = max(0, end - max(start, tier2Boundary))
            consumed = end

            // Travel allowance applies once per day, on the first session with paid hours.
            // Sick days never earn it — `hours` is 0, so this already excludes them.
            let gas: Double
            if hours > 0, gasRemaining > 0 {
                gas = gasRemaining
                gasRemaining = 0
            } else {
                gas = 0
            }

            let basePay: Double
            let tier1Pay: Double
            let tier2Pay: Double
            if isSick {
                let dayKey = calendar.startOfDay(for: session.date)
                let streakNumber = sickStreakDayNumbers[dayKey] ?? 1
                basePay = standard * rate * sickPayPercentage(streakDayNumber: streakNumber)
                tier1Pay = 0
                tier2Pay = 0
            } else {
                let rates = tiers(for: session.dayType)
                basePay = base * rate * rates.base
                tier1Pay = tier1 * rate * rates.tier1
                tier2Pay = tier2 * rate * rates.tier2
            }

            slices.append(Slice(
                session: session,
                base: base,
                tier1: tier1,
                tier2: tier2,
                hours: hours,
                gas: gas,
                basePay: basePay,
                tier1Pay: tier1Pay,
                tier2Pay: tier2Pay,
                gross: basePay + tier1Pay + tier2Pay + gas
            ))
        }

        // Deductions are estimated on the whole day's gross, then apportioned
        // to sessions pro-rata so the parts always sum to the day total.
        let dayGross = slices.reduce(0) { $0 + $1.gross }
        let dayTax = IsraeliTaxEstimator.estimateDailyNet(fromDailyGross: dayGross, settings: settings)
        let points = TaxCreditPointsCalculator.creditPoints(for: settings)

        return slices.map { slice in
            let share = dayGross > 0 ? slice.gross / dayGross : 0
            return (slice.session, DayPayBreakdown(
                regularHours: slice.base,
                ot125Hours: slice.tier1,
                ot150Hours: slice.tier2,
                totalHours: slice.hours,
                gasAllowance: slice.gas,
                basePay: slice.basePay,
                ot125Pay: slice.tier1Pay,
                ot150Pay: slice.tier2Pay,
                totalPay: slice.gross,
                netPay: dayTax.net * share,
                incomeTax: dayTax.incomeTax * share,
                nationalInsurance: dayTax.nationalInsurance * share,
                healthTax: dayTax.healthTax * share,
                creditPointsApplied: dayTax.creditApplied * share,
                creditPoints: points,
                currencyCode: settings.currencyCode
            ))
        }
    }

    /// Day-aware breakdowns for an arbitrary set of sessions, grouped by
    /// calendar day. Order of the result follows clock-in order within each day.
    static func dayAwareBreakdowns(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        calendar: Calendar = .current
    ) -> [(session: WorkSession, breakdown: DayPayBreakdown)] {
        let groups = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        let streaks = sickStreakDayNumbers(sessions: sessions, calendar: calendar)
        return groups
            .sorted { $0.key < $1.key }
            .flatMap {
                breakdowns(forDay: $0.value, settings: settings, sickStreakDayNumbers: streaks, calendar: calendar)
            }
    }

    /// Breakdown of a single session evaluated alone (no same-day context).
    static func breakdown(for session: WorkSession, settings: WorkplaceSettings) -> DayPayBreakdown {
        breakdowns(forDay: [session], settings: settings)[0].breakdown
    }

    /// Breakdown of a single session in the context of all its same-day
    /// sessions, so shared daily allowances are respected.
    static func breakdown(
        for session: WorkSession,
        in allSessions: [WorkSession],
        settings: WorkplaceSettings,
        calendar: Calendar = .current
    ) -> DayPayBreakdown {
        var sameDay = allSessions.filter {
            calendar.isDate($0.date, inSameDayAs: session.date) && !$0.isOpen
        }
        if !sameDay.contains(where: { $0.id == session.id }) {
            sameDay.append(session)
        }
        // Sick-day pricing needs the worker's full sick history, not just
        // this calendar day, to place `session` correctly within its streak.
        let streaks = sickStreakDayNumbers(sessions: allSessions, calendar: calendar)
        let results = breakdowns(forDay: sameDay, settings: settings, sickStreakDayNumbers: streaks, calendar: calendar)
        return results.first { $0.session.id == session.id }?.breakdown
            ?? breakdown(for: session, settings: settings)
    }

    /// Round monetary values to 2 decimal places to avoid floating-point display artefacts.
    private static func round(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static func aggregate(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        calendar: Calendar = .current
    ) -> DayPayBreakdown {
        let completed = sessions.filter { $0.clockOut != nil }
        let totals = dayAwareBreakdowns(
            sessions: completed,
            settings: settings
        ).map(\.breakdown)
        var regular = totals.reduce(0) { $0 + $1.regularHours }
        var ot125 = totals.reduce(0) { $0 + $1.ot125Hours }
        var ot150 = totals.reduce(0) { $0 + $1.ot150Hours }
        let hours = totals.reduce(0) { $0 + $1.totalHours }
        let gas = totals.reduce(0) { $0 + $1.gasAllowance }
        var basePay = totals.reduce(0) { $0 + $1.basePay }
        var ot125Pay = totals.reduce(0) { $0 + $1.ot125Pay }
        var ot150Pay = totals.reduce(0) { $0 + $1.ot150Pay }
        let gross = totals.reduce(0) { $0 + $1.totalPay }
        let net = totals.reduce(0) { $0 + $1.netPay }
        let incomeTax = totals.reduce(0) { $0 + $1.incomeTax }
        let ni = totals.reduce(0) { $0 + $1.nationalInsurance }
        let health = totals.reduce(0) { $0 + $1.healthTax }
        let credit = totals.reduce(0) { $0 + $1.creditPointsApplied }
        let points = TaxCreditPointsCalculator.creditPoints(for: settings)

        // Weekly overtime adjustment (Israeli Hours of Work and Rest Law):
        // Standard week = weeklyStandardHours (default 42). Hours above this threshold
        // that the daily calculator still prices at 100% must be re-priced at 125% (first
        // 2h of weekly OT) then 150% (beyond), mirroring the daily tier structure.
        // Hours already at 125%/150% daily count toward the weekly OT cap so they are
        // not double-charged.
        let rate = settings.hourlyRate
        let dailyOT = ot125 + ot150

        let groupedByWeek = Dictionary(grouping: completed) { session in
            calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: session.clockIn)
        }
        var weeklyExcessHours = 0.0
        for (_, weekSessions) in groupedByWeek {
            let weekTotal = weekSessions.reduce(0) { $0 + $1.effectiveHours }
            weeklyExcessHours += max(0, weekTotal - settings.weeklyStandardHours)
        }

        if weeklyExcessHours > dailyOT {
            let needsWeeklyOT = weeklyExcessHours - dailyOT
            let weeklyOT125 = min(needsWeeklyOT, settings.weeklyOvertimeCapHours)
            let weeklyOT150 = max(0, needsWeeklyOT - settings.weeklyOvertimeCapHours)
            // Move hours from regular bucket to weekly OT buckets:
            // each hour moves from 100% → 125% = extra 25%, or 100% → 150% = extra 50%.
            let promoted125 = min(regular, weeklyOT125)
            let promoted150 = min(regular - promoted125, weeklyOT150)
            regular -= (promoted125 + promoted150)
            ot125 += promoted125
            ot150 += promoted150
            basePay = round(basePay - (promoted125 + promoted150) * rate)
            ot125Pay = round(ot125Pay + promoted125 * rate * 1.25)
            ot150Pay = round(ot150Pay + promoted150 * rate * 1.5)
        }

        let adjustedGross = basePay + ot125Pay + ot150Pay + gas

        return DayPayBreakdown(
            regularHours: regular,
            ot125Hours: ot125,
            ot150Hours: ot150,
            totalHours: hours,
            gasAllowance: round(gas),
            basePay: basePay,
            ot125Pay: ot125Pay,
            ot150Pay: ot150Pay,
            totalPay: round(adjustedGross),
            netPay: round(net),
            incomeTax: round(incomeTax),
            nationalInsurance: round(ni),
            healthTax: round(health),
            creditPointsApplied: round(credit),
            creditPoints: points,
            currencyCode: settings.currencyCode
        )
    }
}
