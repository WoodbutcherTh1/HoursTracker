import Foundation

struct DayPayBreakdown: Equatable {
    let regularHours: Double
    let ot125Hours: Double
    let ot150Hours: Double
    let totalHours: Double
    let gasAllowance: Double
    /// Gross pay (ברוטו) including gas allowance.
    let totalPay: Double
    /// Estimated net pay (נטו).
    let netPay: Double
    let incomeTax: Double
    let nationalInsurance: Double
    let healthTax: Double
    let creditPointsApplied: Double
    let creditPoints: Double

    var grossPay: Double { totalPay }

    var formattedTotalPay: String {
        String(format: "₪%.2f", totalPay)
    }

    var formattedGrossPay: String {
        String(format: "₪%.2f", grossPay)
    }

    var formattedNetPay: String {
        String(format: "₪%.2f", netPay)
    }
}

enum OvertimeCalculator {
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
        let gross = regular * rate + ot125 * rate * 1.25 + ot150 * rate * 1.5 + gas

        let tax = IsraeliTaxEstimator.estimateDailyNet(fromDailyGross: gross, settings: settings)
        let points = TaxCreditPointsCalculator.creditPoints(for: settings)

        return DayPayBreakdown(
            regularHours: regular,
            ot125Hours: ot125,
            ot150Hours: ot150,
            totalHours: totalHours,
            gasAllowance: gas,
            totalPay: gross,
            netPay: tax.net,
            incomeTax: tax.incomeTax,
            nationalInsurance: tax.nationalInsurance,
            healthTax: tax.healthTax,
            creditPointsApplied: tax.creditApplied,
            creditPoints: points
        )
    }

    static func breakdown(for session: WorkSession, settings: WorkplaceSettings) -> DayPayBreakdown {
        breakdown(totalHours: session.totalHours, settings: settings)
    }

    static func aggregate(
        sessions: [WorkSession],
        settings: WorkplaceSettings
    ) -> DayPayBreakdown {
        let totals = sessions.map { breakdown(for: $0, settings: settings) }
        let regular = totals.reduce(0) { $0 + $1.regularHours }
        let ot125 = totals.reduce(0) { $0 + $1.ot125Hours }
        let ot150 = totals.reduce(0) { $0 + $1.ot150Hours }
        let hours = totals.reduce(0) { $0 + $1.totalHours }
        let gas = totals.reduce(0) { $0 + $1.gasAllowance }
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
            totalPay: gross,
            netPay: net,
            incomeTax: incomeTax,
            nationalInsurance: ni,
            healthTax: health,
            creditPointsApplied: credit,
            creditPoints: points
        )
    }
}
