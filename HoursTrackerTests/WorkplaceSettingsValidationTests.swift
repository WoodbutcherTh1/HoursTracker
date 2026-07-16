import XCTest
@testable import HoursTracker

final class WorkplaceSettingsValidationTests: XCTestCase {
    func testInitClampsNumericFields() {
        let settings = WorkplaceSettings(
            workplaceName: "W",
            contractorName: nil,
            workerFullName: "N",
            workerIDNumber: "",
            employeeNumber: "",
            hourlyRate: -10,
            dailyGasAllowance: -5,
            standardDayHours: 0,
            ot125HoursCap: -1,
            locationLatitude: nil,
            locationLongitude: nil,
            locationRadiusMeters: 10,
            numberOfChildren: 99,
            modifiedAt: Date()
        )

        XCTAssertEqual(settings.hourlyRate, 0)
        XCTAssertEqual(settings.dailyGasAllowance, 0)
        XCTAssertEqual(settings.standardDayHours, 0.1, accuracy: 0.0001)
        XCTAssertEqual(settings.ot125HoursCap, 0)
        XCTAssertEqual(settings.locationRadiusMeters, 50)
        XCTAssertEqual(settings.numberOfChildren, 15)
    }

    func testDecodeClampsAbsurdValues() throws {
        let json = """
        {"workplaceName":"X","workerFullName":"W","workerIDNumber":"","employeeNumber":"2",\
        "hourlyRate":-3,"dailyGasAllowance":-1,"standardDayHours":40,"ot125HoursCap":-2,\
        "locationRadiusMeters":99999,"numberOfChildren":-4,"modifiedAt":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let settings = try decoder.decode(WorkplaceSettings.self, from: json)

        XCTAssertEqual(settings.hourlyRate, 0)
        XCTAssertEqual(settings.dailyGasAllowance, 0)
        XCTAssertEqual(settings.standardDayHours, 24, accuracy: 0.0001)
        XCTAssertEqual(settings.ot125HoursCap, 0)
        XCTAssertEqual(settings.locationRadiusMeters, 2_000)
        XCTAssertEqual(settings.numberOfChildren, 0)
    }

    func testIsraeliIDChecksum() {
        XCTAssertTrue(IsraeliIDValidator.isChecksumValid("123456782"))
        XCTAssertFalse(IsraeliIDValidator.isChecksumValid("123456789"))
        XCTAssertFalse(IsraeliIDValidator.shouldWarn(for: ""))
        XCTAssertTrue(IsraeliIDValidator.shouldWarn(for: "123456789"))
        XCTAssertFalse(IsraeliIDValidator.shouldWarn(for: "123456782"))
    }
}
