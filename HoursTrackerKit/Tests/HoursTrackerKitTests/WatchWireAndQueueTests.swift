import XCTest
@testable import HoursTrackerKit

final class WatchWireAndQueueTests: XCTestCase {
    func testWireRoundTripSnapshotAndClockEvent() throws {
        let pay = WatchPaySettings(
            hourlyRate: 50,
            dailyGasAllowance: 35,
            standardDayHours: 8.6,
            ot125HoursCap: 2,
            nightStandardDayHours: 7,
            defaultBreakMinutes: 0,
            restDayWeekday: 7,
            secondRestDayWeekday: nil,
            currencyCode: "ILS",
            language: .hebrew
        )
        let session = WorkSession(
            date: Calendar.current.startOfDay(for: Date()),
            clockIn: Date().addingTimeInterval(-3600),
            clockOut: Date()
        )
        let snap = WatchSnapshot(sessions: [session], paySettings: pay)
        let encoded = try WatchWireCodec.encode(.snapshot(snap))
        let decoded = try WatchWireCodec.decode(encoded)
        guard case .snapshot(let got) = decoded else {
            return XCTFail("expected snapshot")
        }
        XCTAssertEqual(got.sessions.count, 1)
        XCTAssertEqual(got.paySettings.hourlyRate, 50)
        XCTAssertEqual(got.paySettings.language, .hebrew)
        // Never serialize worker ID through WatchPaySettings.
        XCTAssertEqual(got.paySettings.workplaceSettingsForGrossEstimate().workerIDNumber, "")

        let event = WatchClockEvent.makeClockIn()
        let eventData = try WatchWireCodec.encode(.clockEvent(event))
        let eventDecoded = try WatchWireCodec.decode(eventData)
        guard case .clockEvent(let e) = eventDecoded else {
            return XCTFail("expected clockEvent")
        }
        XCTAssertEqual(e.id, event.id)
        XCTAssertEqual(e.kind, .clockIn)
    }

    func testDictionaryPacking() throws {
        let event = WatchClockEvent.makeClockOut(sessionID: UUID())
        let dict = try WatchWireCodec.dictionary(for: .clockEvent(event))
        let message = try WatchWireCodec.message(from: dict)
        guard case .clockEvent(let e) = message else {
            return XCTFail("expected clockEvent")
        }
        XCTAssertEqual(e.id, event.id)
    }

    func testPendingQueueEnqueueFlushDedupe() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let queue = WatchPendingActionQueue(directory: dir)

        let a = WatchClockEvent.makeClockIn()
        let b = WatchClockEvent.makeClockOut(sessionID: a.sessionID)
        queue.enqueue(a)
        queue.enqueue(a) // duplicate id ignored
        queue.enqueue(b)
        XCTAssertEqual(queue.pending.count, 2)

        // Reload from disk
        let reloaded = WatchPendingActionQueue(directory: dir)
        XCTAssertEqual(reloaded.pending.map(\.id), [a.id, b.id])

        reloaded.removeAcknowledged(ids: [a.id])
        XCTAssertEqual(reloaded.pending.map(\.id), [b.id])
        reloaded.remove(id: b.id)
        XCTAssertTrue(reloaded.pending.isEmpty)
    }

    func testDedupeStore() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = WatchEventDedupeStore(defaults: defaults)
        let id = UUID()
        XCTAssertFalse(store.contains(id))
        store.insert(id)
        XCTAssertTrue(store.contains(id))
        store.insert(id)
        XCTAssertTrue(store.contains(id))
    }

    func testWatchGrossMatchesOvertimeCalculatorAggregate() {
        var settings = WorkplaceSettings.default
        settings.hourlyRate = 40
        settings.dailyGasAllowance = 0
        settings.standardDayHours = 8.6
        settings.ot125HoursCap = 2
        settings.currencyCode = "ILS"

        let day = Calendar.current.startOfDay(for: Date())
        let inTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
        let outTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day)!
        let session = WorkSession(
            date: day,
            clockIn: inTime,
            clockOut: outTime,
            dayType: .regular
        )

        let pay = WatchPaySettings(from: settings, language: .english)
        let watch = WatchGrossEstimate.todayGross(
            sessions: [session],
            paySettings: pay,
            now: day.addingTimeInterval(12 * 3600)
        )
        let phone = OvertimeCalculator.aggregate(sessions: [session], settings: settings)
        XCTAssertEqual(watch.totalPay, phone.totalPay, accuracy: 0.001)
        XCTAssertEqual(watch.totalHours, phone.totalHours, accuracy: 0.001)
    }
}
