import XCTest
import HoursTrackerKit
@testable import HoursTrackerWatch

/// Host-side sanity: pending queue used by the watch target behaves under watchOS.
final class WatchPendingQueueHostTests: XCTestCase {
    func testQueuePersistsOnWatchDocumentsPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-q-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let queue = WatchPendingActionQueue(directory: dir)
        let event = WatchClockEvent.makeClockIn()
        queue.enqueue(event)
        let again = WatchPendingActionQueue(directory: dir)
        XCTAssertEqual(again.pending.first?.id, event.id)
    }
}
