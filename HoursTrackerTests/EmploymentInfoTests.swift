import XCTest
@testable import HoursTracker

final class EmploymentInfoTests: XCTestCase {
    private func settings() -> WorkplaceSettings {
        var s = WorkplaceSettings.default
        s.hourlyRate = 50
        s.dailyGasAllowance = 0
        s.employment.type = .direct
        s.employment.directHireDate = TestData.date(2026, 10, 1)
        s.employment.contractorTerms = ContractorTerms(hourlyRate: 40, dailyGasAllowance: 0, contractorName: "X")
        return s
    }

    func testShiftBeforeHireUsesContractorRate() {
        let s = settings()
        let before = OvertimeCalculator.breakdown(for: TestData.session(day: 15), settings: s)
        XCTAssertEqual(s.effectiveTerms(on: TestData.date(2026, 9, 15)).hourlyRate, 40)
        XCTAssertEqual(s.effectiveTerms(on: TestData.date(2026, 10, 1)).hourlyRate, 50)
        XCTAssertGreaterThan(before.basePay, 0)
    }

    func testPensionLowersNetAndAddsEmployerParts() {
        var s = settings()
        s.employment.directHireDate = nil
        s.employment.contractorTerms = nil
        let session = TestData.session(day: 15)
        let without = OvertimeCalculator.breakdown(for: session, settings: s)
        s.employment.pensionEnabled = true
        let with = OvertimeCalculator.breakdown(for: session, settings: s)
        XCTAssertGreaterThan(with.pensionEmployee, 0)
        XCTAssertGreaterThan(with.pensionEmployer, 0)
        XCTAssertGreaterThan(with.severance, 0)
        XCTAssertEqual(with.netPay, without.netPay - with.pensionEmployee, accuracy: 0.01)
        XCTAssertEqual(with.totalPay, without.totalPay, accuracy: 0.001)
    }

    func testNineMonthMark() {
        var info = EmploymentInfo()
        info.type = .contractor
        info.startDate = TestData.date(2026, 6, 26)
        XCTAssertEqual(info.contractorLimitDate.map { Calendar.current.component(.month, from: $0) }, 3)
    }

    func testOldSettingsDecodeWithoutEmployment() throws {
        let data = try JSONEncoder().encode(WorkplaceSettings.default)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "employment")
        let old = try JSONDecoder().decode(WorkplaceSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.employment.type)
    }
}
