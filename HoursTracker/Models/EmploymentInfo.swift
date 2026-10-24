import Foundation

/// How the worker is employed at a workplace.
enum EmploymentType: String, Codable, CaseIterable, Identifiable {
    /// Works at a company but is hired and paid by a contractor (עובד קבלן).
    case contractor
    /// Hired and paid by the company itself (עובד חברה).
    case direct

    var id: String { rawValue }
}

/// The terms that applied while the worker was still on the contractor's payroll.
struct ContractorTerms: Codable, Equatable {
    var hourlyRate: Double
    var dailyGasAllowance: Double
    var contractorName: String?
}

/// Pension (פנסיה) and severance (פיצויים) percentages of gross pay. Defaults are the
/// statutory minimums for pension (6% employee, 6.5% employer) and severance (6%).
struct PensionTerms: Codable, Equatable {
    var employeePercent = 6.0
    var employerPercent = 6.5
    var severancePercent = 6.0
    /// First day contributions count; nil = from the day the company hired the worker.
    var startDate: Date?
}

/// Employment type, the contractor → company transition, and pension terms for one
/// workplace. Everything optional/defaulted so older saved settings decode unchanged.
struct EmploymentInfo: Codable, Equatable {
    /// nil = the worker hasn't said (older installs).
    var type: EmploymentType?
    /// First day at this workplace.
    var startDate: Date?
    /// The day the company took the worker on directly (after the contractor).
    var directHireDate: Date?
    /// Terms before `directHireDate`; shifts on earlier days are priced with these.
    var contractorTerms: ContractorTerms?
    var pensionEnabled = false
    var pension = PensionTerms()

    /// Months a contractor placement may last at one company.
    static let contractorMonthsLimit = 9

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try? c.decodeIfPresent(EmploymentType.self, forKey: .type)
        startDate = try? c.decodeIfPresent(Date.self, forKey: .startDate)
        directHireDate = try? c.decodeIfPresent(Date.self, forKey: .directHireDate)
        contractorTerms = try? c.decodeIfPresent(ContractorTerms.self, forKey: .contractorTerms)
        pensionEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .pensionEnabled)) ?? false
        pension = (try? c.decodeIfPresent(PensionTerms.self, forKey: .pension)) ?? PensionTerms()
    }

    /// The day a contractor placement started on `startDate` reaches 9 months.
    var contractorLimitDate: Date? {
        guard type == .contractor, let startDate else { return nil }
        return Calendar.current.date(byAdding: .month, value: Self.contractorMonthsLimit, to: startDate)
    }

    /// Whole days until the 9-month mark (negative once passed).
    func daysUntilContractorLimit(from now: Date = Date()) -> Int? {
        guard let limit = contractorLimitDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: limit)).day
    }

    /// Whether pension/severance count on `date`.
    func pensionActive(on date: Date) -> Bool {
        guard type == .direct, pensionEnabled else { return false }
        let calendar = Calendar.current
        let start = pension.startDate ?? directHireDate ?? startDate
        guard let start else { return true }
        return calendar.startOfDay(for: date) >= calendar.startOfDay(for: start)
    }
}

extension WorkplaceSettings {
    /// These settings with the hourly rate and travel allowance that applied on `date`:
    /// before the company took the worker on directly, the contractor's terms.
    func effectiveTerms(on date: Date) -> WorkplaceSettings {
        guard let hire = employment.directHireDate, let old = employment.contractorTerms,
              Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: hire) else { return self }
        var copy = self
        copy.hourlyRate = old.hourlyRate
        copy.dailyGasAllowance = old.dailyGasAllowance
        return copy
    }
}
