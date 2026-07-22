import XCTest
import CoreLocation
@testable import HoursTracker

final class LocationPermissionFlowTests: XCTestCase {
    func testCaptureHelperRequestsLocationOnlyAfterAuthorization() {
        XCTAssertFalse(LocationCaptureHelper.shouldRequestLocation(for: .notDetermined))
        XCTAssertFalse(LocationCaptureHelper.shouldRequestLocation(for: .denied))
        XCTAssertFalse(LocationCaptureHelper.shouldRequestLocation(for: .restricted))
        XCTAssertTrue(LocationCaptureHelper.shouldRequestLocation(for: .authorizedWhenInUse))
        XCTAssertTrue(LocationCaptureHelper.shouldRequestLocation(for: .authorizedAlways))
    }

    func testInfoPlistOmitsBackgroundLocationModeAndDeprecatedAlwaysKey() {
        let info = Bundle.main.infoDictionary ?? [:]
        // Guideline 2.5.4: do not declare UIBackgroundModes location.
        // Arrival reminders use region monitoring only (no continuous updates).
        let backgroundModes = info["UIBackgroundModes"] as? [String] ?? []
        XCTAssertTrue(backgroundModes.isEmpty, "UIBackgroundModes must be absent/empty")
        XCTAssertFalse(backgroundModes.contains("location"))
        XCTAssertNil(info["NSLocationAlwaysUsageDescription"])
        XCTAssertNotNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"])
        XCTAssertNotNil(info["NSLocationWhenInUseUsageDescription"])
    }
}
