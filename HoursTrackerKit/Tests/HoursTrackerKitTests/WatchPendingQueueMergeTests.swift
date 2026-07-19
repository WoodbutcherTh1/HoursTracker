import XCTest
@testable import HoursTrackerKit

final class WatchPendingQueueMergeTests: XCTestCase {
    func testEnqueuePersistsAndReloads() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shared_pending_clock_events.json")

        let queue = WatchPendingActionQueue(fileURL: url)
        let event = WatchClockEvent.makeClockIn()
        queue.enqueue(event)

        let again = WatchPendingActionQueue(fileURL: url)
        XCTAssertEqual(again.pending.map(\.id), [event.id])
    }

    func testMergeDiskPicksUpExternalWriter() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-ext-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shared_pending_clock_events.json")

        let queue = WatchPendingActionQueue(fileURL: url)
        let first = WatchClockEvent.makeClockIn()
        queue.enqueue(first)

        // Simulate WidgetPendingEventStore writing the same file.
        let second = WatchClockEvent.makeClockOut(sessionID: first.sessionID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([first, second])
        try data.write(to: url, options: [.atomic])

        XCTAssertEqual(Set(queue.pending.map(\.id)), Set([first.id, second.id]))
    }
}
