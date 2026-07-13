import Foundation

struct WorkplaceSettings: Codable, Equatable {
    var workplaceName: String
    var contractorName: String?
    var workerFullName: String
    var workerIDNumber: String
    var employeeNumber: String
    var hourlyRate: Double
    var dailyGasAllowance: Double
    var standardDayHours: Double
    var ot125HoursCap: Double
    var locationLatitude: Double?
    var locationLongitude: Double?
    var locationRadiusMeters: Double
    var maritalStatus: MaritalStatus
    var hasChildren: Bool
    var numberOfChildren: Int
    var spouseEmployed: Bool
    /// Day of month when the payroll cycle starts (1...28). Default 1 = calendar month.
    var payrollStartDay: Int
    var modifiedAt: Date

    static let `default` = WorkplaceSettings(
        workplaceName: "Kahana",
        contractorName: nil,
        workerFullName: "",
        workerIDNumber: "",
        employeeNumber: "",
        hourlyRate: 0,
        dailyGasAllowance: 35,
        standardDayHours: 8.6,
        ot125HoursCap: 2.0,
        locationLatitude: nil,
        locationLongitude: nil,
        locationRadiusMeters: 150,
        maritalStatus: .single,
        hasChildren: false,
        numberOfChildren: 0,
        spouseEmployed: false,
        payrollStartDay: 1,
        modifiedAt: Date()
    )

    var hasWorkplaceLocation: Bool {
        locationLatitude != nil && locationLongitude != nil
    }

    var creditPoints: Double {
        TaxCreditPointsCalculator.creditPoints(for: self)
    }

    enum CodingKeys: String, CodingKey {
        case workplaceName, contractorName, workerFullName, workerIDNumber, employeeNumber
        case hourlyRate, dailyGasAllowance, standardDayHours, ot125HoursCap
        case locationLatitude, locationLongitude, locationRadiusMeters
        case maritalStatus, hasChildren, numberOfChildren, spouseEmployed, payrollStartDay, modifiedAt
    }

    init(
        workplaceName: String,
        contractorName: String?,
        workerFullName: String,
        workerIDNumber: String,
        employeeNumber: String,
        hourlyRate: Double,
        dailyGasAllowance: Double,
        standardDayHours: Double,
        ot125HoursCap: Double,
        locationLatitude: Double?,
        locationLongitude: Double?,
        locationRadiusMeters: Double,
        maritalStatus: MaritalStatus = .single,
        hasChildren: Bool = false,
        numberOfChildren: Int = 0,
        spouseEmployed: Bool = false,
        payrollStartDay: Int = 1,
        modifiedAt: Date
    ) {
        self.workplaceName = workplaceName
        self.contractorName = contractorName
        self.workerFullName = workerFullName
        self.workerIDNumber = workerIDNumber
        self.employeeNumber = employeeNumber
        self.hourlyRate = hourlyRate
        self.dailyGasAllowance = dailyGasAllowance
        self.standardDayHours = standardDayHours
        self.ot125HoursCap = ot125HoursCap
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.locationRadiusMeters = locationRadiusMeters
        self.maritalStatus = maritalStatus
        self.hasChildren = hasChildren
        self.numberOfChildren = numberOfChildren
        self.spouseEmployed = spouseEmployed
        self.payrollStartDay = HistoryPeriodHelper.normalizedStartDay(payrollStartDay)
        self.modifiedAt = modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workplaceName = try c.decode(String.self, forKey: .workplaceName)
        contractorName = try c.decodeIfPresent(String.self, forKey: .contractorName)
        workerFullName = try c.decode(String.self, forKey: .workerFullName)
        workerIDNumber = try c.decode(String.self, forKey: .workerIDNumber)
        employeeNumber = try c.decode(String.self, forKey: .employeeNumber)
        hourlyRate = try c.decode(Double.self, forKey: .hourlyRate)
        dailyGasAllowance = try c.decode(Double.self, forKey: .dailyGasAllowance)
        standardDayHours = try c.decode(Double.self, forKey: .standardDayHours)
        ot125HoursCap = try c.decode(Double.self, forKey: .ot125HoursCap)
        locationLatitude = try c.decodeIfPresent(Double.self, forKey: .locationLatitude)
        locationLongitude = try c.decodeIfPresent(Double.self, forKey: .locationLongitude)
        locationRadiusMeters = try c.decode(Double.self, forKey: .locationRadiusMeters)
        maritalStatus = try c.decodeIfPresent(MaritalStatus.self, forKey: .maritalStatus) ?? .single
        hasChildren = try c.decodeIfPresent(Bool.self, forKey: .hasChildren) ?? false
        numberOfChildren = try c.decodeIfPresent(Int.self, forKey: .numberOfChildren) ?? 0
        spouseEmployed = try c.decodeIfPresent(Bool.self, forKey: .spouseEmployed) ?? false
        payrollStartDay = HistoryPeriodHelper.normalizedStartDay(
            try c.decodeIfPresent(Int.self, forKey: .payrollStartDay) ?? 1
        )
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }
}
