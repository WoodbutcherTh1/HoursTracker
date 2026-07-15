import XCTest
@testable import HoursTracker

final class StickmanDayStyleTests: XCTestCase {
    func testEachCalendarDayHasADistinctStyle() {
        let styles = (1...31).map { StickmanDayStyle.style(forDayOfMonth: $0) }

        // Every day must differ in at least pose, accessory, or motion.
        for i in 0..<styles.count {
            for j in (i + 1)..<styles.count {
                let a = styles[i]
                let b = styles[j]
                let sameLook =
                    a.pose == b.pose
                    && a.accessory == b.accessory
                    && a.motion == b.motion
                    && a.facingLeft == b.facingLeft
                XCTAssertFalse(
                    sameLook,
                    "Day \(i + 1) and day \(j + 1) share the same pose/accessory/motion/facing"
                )
            }
        }
    }

    func testDayOfMonthIsClampedToCatalogRange() {
        let low = StickmanDayStyle.style(forDayOfMonth: 0)
        let high = StickmanDayStyle.style(forDayOfMonth: 99)
        XCTAssertEqual(low, StickmanDayStyle.style(forDayOfMonth: 1))
        XCTAssertEqual(high, StickmanDayStyle.style(forDayOfMonth: 31))
    }
}
