import Foundation

/// Israeli tax credit points (נקודות זיכוי) — simplified baseline rules.
public enum TaxCreditPointsCalculator {
    /// Base points for an Israeli resident.
    public static let baseResidentPoints: Double = 2.25

    /// Approximate monthly value of one credit point (₪), 2025 baseline.
    public static let creditPointMonthlyValueILS: Double = 242

    /// Average working days used to spread monthly credits/deductions onto a single day.
    public static let averageWorkingDaysPerMonth: Double = 21.67

    public static func creditPoints(for settings: WorkplaceSettings) -> Double {
        var points = baseResidentPoints

        if settings.hasChildren {
            points += Double(max(0, settings.numberOfChildren))
        }

        // Married + spouse not employed: simplified extra half-point estimate.
        if settings.maritalStatus == .married && !settings.spouseEmployed {
            points += 0.5
        }

        return points
    }

    public static func monthlyCreditValue(for settings: WorkplaceSettings) -> Double {
        creditPoints(for: settings) * creditPointMonthlyValueILS
    }

    public static func dailyCreditValue(for settings: WorkplaceSettings) -> Double {
        monthlyCreditValue(for: settings) / averageWorkingDaysPerMonth
    }
}
