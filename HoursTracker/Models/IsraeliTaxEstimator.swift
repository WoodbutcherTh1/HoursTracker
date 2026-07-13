import Foundation

/// Estimated Israeli income tax, National Insurance, and Health Tax for net pay.
/// Figures are approximate planning estimates — not a payroll / tax authority calculation.
enum IsraeliTaxEstimator {
    private static let averageWageThresholdMonthly: Double = 7_522

    /// Monthly income-tax brackets (approximate, employee-side estimate).
    private static let monthlyBrackets: [(limit: Double, rate: Double)] = [
        (7_010, 0.10),
        (10_060, 0.14),
        (16_150, 0.20),
        (22_440, 0.31),
        (46_690, 0.35),
        (60_130, 0.47),
        (.greatestFiniteMagnitude, 0.50)
    ]

    struct MonthlyDeductions: Equatable {
        let incomeTax: Double
        let nationalInsurance: Double
        let healthTax: Double
        let creditOffset: Double

        var total: Double {
            max(0, incomeTax + nationalInsurance + healthTax - creditOffset)
        }
    }

    static func estimateMonthlyDeductions(
        monthlyGross: Double,
        settings: WorkplaceSettings
    ) -> MonthlyDeductions {
        let gross = max(0, monthlyGross)
        let rawIncomeTax = progressiveTax(on: gross)
        let credit = TaxCreditPointsCalculator.monthlyCreditValue(for: settings)
        let incomeTax = max(0, rawIncomeTax - credit)
        let ni = nationalInsurance(on: gross)
        let health = healthTax(on: gross)

        return MonthlyDeductions(
            incomeTax: incomeTax,
            nationalInsurance: ni,
            healthTax: health,
            creditOffset: min(credit, rawIncomeTax)
        )
    }

    /// Scale a single day's gross into an estimated monthly profile, then back to daily net.
    static func estimateDailyNet(fromDailyGross dailyGross: Double, settings: WorkplaceSettings) -> (
        net: Double,
        incomeTax: Double,
        nationalInsurance: Double,
        healthTax: Double,
        creditApplied: Double
    ) {
        let days = TaxCreditPointsCalculator.averageWorkingDaysPerMonth
        let monthlyGross = dailyGross * days
        let monthly = estimateMonthlyDeductions(monthlyGross: monthlyGross, settings: settings)

        return (
            net: max(0, dailyGross - monthly.total / days),
            incomeTax: monthly.incomeTax / days,
            nationalInsurance: monthly.nationalInsurance / days,
            healthTax: monthly.healthTax / days,
            creditApplied: monthly.creditOffset / days
        )
    }

    private static func progressiveTax(on income: Double) -> Double {
        var remaining = income
        var previousLimit = 0.0
        var tax = 0.0

        for bracket in monthlyBrackets {
            let slice = min(remaining, bracket.limit - previousLimit)
            guard slice > 0 else { break }
            tax += slice * bracket.rate
            remaining -= slice
            previousLimit = bracket.limit
            if remaining <= 0 { break }
        }
        return tax
    }

    private static func nationalInsurance(on monthlyGross: Double) -> Double {
        let reduced = min(monthlyGross, averageWageThresholdMonthly) * 0.004
        let full = max(0, monthlyGross - averageWageThresholdMonthly) * 0.07
        return reduced + full
    }

    private static func healthTax(on monthlyGross: Double) -> Double {
        let reduced = min(monthlyGross, averageWageThresholdMonthly) * 0.031
        let full = max(0, monthlyGross - averageWageThresholdMonthly) * 0.05
        return reduced + full
    }
}
