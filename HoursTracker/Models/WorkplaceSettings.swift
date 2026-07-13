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
        modifiedAt: Date()
    )

    var hasWorkplaceLocation: Bool {
        locationLatitude != nil && locationLongitude != nil
    }
}
