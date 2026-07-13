import XCTest
@testable import HoursTracker

final class OvertimeCalculatorTests: XCTestCase {
    private var settings: WorkplaceSettings!

    override func setUp() {
        super.setUp()
        settings = WorkplaceSettings(
            workplaceName: "Test",
            contractorName: nil,
            workerFullName: "Worker",
            workerIDNumber: "123",
            employeeNumber: "456",
            hourlyRate: 100,
            dailyGasAllowance: 35,
            standardDayHours: 8.6,
            ot125HoursCap: 2.0,
            locationLatitude: nil,
            locationLongitude: nil,
            locationRadiusMeters: 150,
            modifiedAt: Date()
        )
    }

    func testRegularHoursOnly() {
        let result = OvertimeCalculator.breakdown(totalHours: 8.0, settings: settings)
        XCTAssertEqual(result.regularHours, 8.0, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.totalPay, 835, accuracy: 0.01) // 800 + 35 gas
    }

    func testExactlyStandardDayHours() {
        let result = OvertimeCalculator.breakdown(totalHours: 8.6, settings: settings)
        XCTAssertEqual(result.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.totalPay, 895, accuracy: 0.01) // 860 + 35
    }

    func testOT125Only() {
        let result = OvertimeCalculator.breakdown(totalHours: 10.0, settings: settings)
        XCTAssertEqual(result.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 1.4, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.001)
        // 860 + 1.4*125 + 35 = 1070
        XCTAssertEqual(result.totalPay, 1070, accuracy: 0.01)
    }

    func testOT125CapAndOT150() {
        let result = OvertimeCalculator.breakdown(totalHours: 12.0, settings: settings)
        XCTAssertEqual(result.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 2.0, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 1.4, accuracy: 0.001)
        // 860 + 250 + 210 + 35 = 1355
        XCTAssertEqual(result.totalPay, 1355, accuracy: 0.01)
    }

    func testZeroHours() {
        let result = OvertimeCalculator.breakdown(totalHours: 0, settings: settings)
        XCTAssertEqual(result.regularHours, 0, accuracy: 0.001)
        XCTAssertEqual(result.totalPay, 35, accuracy: 0.01)
    }

    func testAggregateMultipleSessions() {
        let sessions = [
            makeSession(hours: 8.6),
            makeSession(hours: 10.0)
        ]
        let result = OvertimeCalculator.aggregate(sessions: sessions, settings: settings)
        XCTAssertEqual(result.regularHours, 17.2, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 1.4, accuracy: 0.001)
        XCTAssertEqual(result.gasAllowance, 70, accuracy: 0.01)
    }

    private func makeSession(hours: Double) -> WorkSession {
        let start = Date()
        let end = start.addingTimeInterval(hours * 3600)
        return WorkSession(
            date: start,
            clockIn: start,
            clockOut: end,
            isManualEntry: false
        )
    }
}
