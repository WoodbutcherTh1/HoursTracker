import Foundation

public struct DayPayBreakdown: Equatable {
    /// Base-rate hours: 100% on regular days, 150% on rest days / holidays.
    public let regularHours: Double
    /// First overtime tier: 125% on regular days, 175% on rest days / holidays.
    public let ot125Hours: Double
    /// Second overtime tier: 150% on regular days, 200% on rest days / holidays.
    public let ot150Hours: Double
    public let totalHours: Double
    public let gasAllowance: Double
    public let basePay: Double
    public let ot125Pay: Double
    public let ot150Pay: Double
    /// Gross pay (ברוטו) including gas allowance.
    public let totalPay: Double
    /// Estimated net pay (נטו).
    public let netPay: Double
    public let incomeTax: Double
    public let nationalInsurance: Double
    public let healthTax: Double
    public let creditPointsApplied: Double
    public let creditPoints: Double
    public let currencyCode: String

    public var grossPay: Double { totalPay }

    public func formatted(_ amount: Double) -> String {
        PayFormatter.string(amount, currencyCode: currencyCode)
    }

    public var formattedTotalPay: String { formatted(totalPay) }

    public var formattedGrossPay: String { formatted(grossPay) }

    public var formattedNetPay: String { formatted(netPay) }

    public init(
        regularHours: Double,
        ot125Hours: Double,
        ot150Hours: Double,
        totalHours: Double,
        gasAllowance: Double,
        basePay: Double,
        ot125Pay: Double,
        ot150Pay: Double,
        totalPay: Double,
        netPay: Double,
        incomeTax: Double,
        nationalInsurance: Double,
        healthTax: Double,
        creditPointsApplied: Double,
        creditPoints: Double,
        currencyCode: String
    ) {
        self.regularHours = regularHours
        self.ot125Hours = ot125Hours
        self.ot150Hours = ot150Hours
        self.totalHours = totalHours
        self.gasAllowance = gasAllowance
        self.basePay = basePay
        self.ot125Pay = ot125Pay
        self.ot150Pay = ot150Pay
        self.totalPay = totalPay
        self.netPay = netPay
        self.incomeTax = incomeTax
        self.nationalInsurance = nationalInsurance
        self.healthTax = healthTax
        self.creditPointsApplied = creditPointsApplied
        self.creditPoints = creditPoints
        self.currencyCode = currencyCode
    }
}

public enum OvertimeCalculator {
    public struct RateTiers: Equatable {
        public let base: Double
        public let tier1: Double
        public let tier2: Double

        public init(base: Double, tier1: Double, tier2: Double) {
            self.base = base
            self.tier1 = tier1
            self.tier2 = tier2
        }
    }

    public static func tiers(for dayType: DayType) -> RateTiers {
        switch dayType {
        case .regular:
            return RateTiers(base: 1.0, tier1: 1.25, tier2: 1.5)
        case .restDay, .holiday:
            // Rest-day / holiday work pays 150% from the first hour;
            // overtime tiers add the same +25% / +50% on top.
            return RateTiers(base: 1.5, tier1: 1.75, tier2: 2.0)
        }
    }

    public static func standardHours(for session: WorkSession, settings: WorkplaceSettings) -> Double {
        session.isNightShift ? settings.nightStandardDayHours : settings.standardDayHours
    }

    /// Simple regular-day breakdown from a raw hours total. Kept for callers
    /// that have no session context (previews, quick estimates, older tests).
    public static func breakdown(
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
    public static func breakdowns(
        forDay daySessions: [WorkSession],
        settings: WorkplaceSettings
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
            let hours = session.effectiveHours
            let standard = standardHours(for: session, settings: settings)
            let tier1Boundary = standard
            let tier2Boundary = standard + settings.ot125HoursCap

            let start = consumed
            let end = start + hours
            let base = max(0, min(end, tier1Boundary) - start)
            let tier1 = max(0, min(end, tier2Boundary) - max(start, tier1Boundary))
            let tier2 = max(0, end - max(start, tier2Boundary))
            consumed = end

            let rates = tiers(for: session.dayType)
            // Travel allowance applies once per day, on the first session with paid hours.
            let gas: Double
            if hours > 0, gasRemaining > 0 {
                gas = gasRemaining
                gasRemaining = 0
            } else {
                gas = 0
            }

            let basePay = base * rate * rates.base
            let tier1Pay = tier1 * rate * rates.tier1
            let tier2Pay = tier2 * rate * rates.tier2

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
    public static func dayAwareBreakdowns(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        calendar: Calendar = .current
    ) -> [(session: WorkSession, breakdown: DayPayBreakdown)] {
        let groups = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return groups
            .sorted { $0.key < $1.key }
            .flatMap { breakdowns(forDay: $0.value, settings: settings) }
    }

    /// Breakdown of a single session evaluated alone (no same-day context).
    public static func breakdown(for session: WorkSession, settings: WorkplaceSettings) -> DayPayBreakdown {
        breakdowns(forDay: [session], settings: settings)[0].breakdown
    }

    /// Breakdown of a single session in the context of all its same-day
    /// sessions, so shared daily allowances are respected.
    public static func breakdown(
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
        let results = breakdowns(forDay: sameDay, settings: settings)
        return results.first { $0.session.id == session.id }?.breakdown
            ?? breakdown(for: session, settings: settings)
    }

    public static func aggregate(
        sessions: [WorkSession],
        settings: WorkplaceSettings
    ) -> DayPayBreakdown {
        let totals = dayAwareBreakdowns(sessions: sessions, settings: settings).map(\.breakdown)
        let regular = totals.reduce(0) { $0 + $1.regularHours }
        let ot125 = totals.reduce(0) { $0 + $1.ot125Hours }
        let ot150 = totals.reduce(0) { $0 + $1.ot150Hours }
        let hours = totals.reduce(0) { $0 + $1.totalHours }
        let gas = totals.reduce(0) { $0 + $1.gasAllowance }
        let basePay = totals.reduce(0) { $0 + $1.basePay }
        let ot125Pay = totals.reduce(0) { $0 + $1.ot125Pay }
        let ot150Pay = totals.reduce(0) { $0 + $1.ot150Pay }
        let gross = totals.reduce(0) { $0 + $1.totalPay }
        let net = totals.reduce(0) { $0 + $1.netPay }
        let incomeTax = totals.reduce(0) { $0 + $1.incomeTax }
        let ni = totals.reduce(0) { $0 + $1.nationalInsurance }
        let health = totals.reduce(0) { $0 + $1.healthTax }
        let credit = totals.reduce(0) { $0 + $1.creditPointsApplied }
        let points = TaxCreditPointsCalculator.creditPoints(for: settings)

        return DayPayBreakdown(
            regularHours: regular,
            ot125Hours: ot125,
            ot150Hours: ot150,
            totalHours: hours,
            gasAllowance: gas,
            basePay: basePay,
            ot125Pay: ot125Pay,
            ot150Pay: ot150Pay,
            totalPay: gross,
            netPay: net,
            incomeTax: incomeTax,
            nationalInsurance: ni,
            healthTax: health,
            creditPointsApplied: credit,
            creditPoints: points,
            currencyCode: settings.currencyCode
        )
    }
}
