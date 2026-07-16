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
    /// Weekly rest day in `Calendar` weekday numbering (1 = Sunday ... 7 = Saturday).
    var restDayWeekday: Int
    /// Unpaid break applied automatically to shifts of 6 hours or more.
    var defaultBreakMinutes: Int
    /// Standard day for night shifts before overtime starts (Hours of Work and Rest Law).
    var nightStandardDayHours: Double
    /// ISO 4217 currency code used for all pay display.
    var currencyCode: String
    /// User opted into workplace arrival reminders (requires Always location).
    var arrivalRemindersEnabled: Bool
    var modifiedAt: Date

    static let `default` = WorkplaceSettings(
        workplaceName: "",
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
        restDayWeekday: 7,
        defaultBreakMinutes: 0,
        nightStandardDayHours: 7.0,
        currencyCode: "ILS",
        arrivalRemindersEnabled: false,
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
        case maritalStatus, hasChildren, numberOfChildren, spouseEmployed, payrollStartDay
        case restDayWeekday, defaultBreakMinutes, nightStandardDayHours, currencyCode
        case arrivalRemindersEnabled
        case modifiedAt
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
        restDayWeekday: Int = 7,
        defaultBreakMinutes: Int = 0,
        nightStandardDayHours: Double = 7.0,
        currencyCode: String = "ILS",
        arrivalRemindersEnabled: Bool = false,
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
        self.payrollStartDay = payrollStartDay
        self.restDayWeekday = restDayWeekday
        self.defaultBreakMinutes = defaultBreakMinutes
        self.nightStandardDayHours = nightStandardDayHours
        self.currencyCode = currencyCode
        self.arrivalRemindersEnabled = arrivalRemindersEnabled
        self.modifiedAt = modifiedAt
        normalizeValidatedFields()
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
        payrollStartDay = try c.decodeIfPresent(Int.self, forKey: .payrollStartDay) ?? 1
        restDayWeekday = try c.decodeIfPresent(Int.self, forKey: .restDayWeekday) ?? 7
        defaultBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultBreakMinutes) ?? 0
        nightStandardDayHours = try c.decodeIfPresent(Double.self, forKey: .nightStandardDayHours) ?? 7.0
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? "ILS"
        arrivalRemindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .arrivalRemindersEnabled) ?? false
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        normalizeValidatedFields()
    }

    /// Single source of truth for numeric bounds (init + decode).
    mutating func normalizeValidatedFields() {
        hourlyRate = max(0, hourlyRate)
        dailyGasAllowance = max(0, dailyGasAllowance)
        // Open-closed interval (0, 24]
        standardDayHours = min(24, max(0.1, standardDayHours))
        ot125HoursCap = max(0, ot125HoursCap)
        locationRadiusMeters = min(2_000, max(50, locationRadiusMeters))
        numberOfChildren = min(15, max(0, numberOfChildren))
        payrollStartDay = HistoryPeriodHelper.normalizedStartDay(payrollStartDay)
        restDayWeekday = min(max(restDayWeekday, 1), 7)
        defaultBreakMinutes = max(0, defaultBreakMinutes)
        nightStandardDayHours = min(24, max(0.1, nightStandardDayHours))
    }
}
