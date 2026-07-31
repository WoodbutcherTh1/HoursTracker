import XCTest
import CloudKit
@testable import HoursTracker

final class SyncConflictResolutionTests: XCTestCase {
    private let manager = CloudKitSyncManager.shared

    private var payloadEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var payloadDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func serverSessionRecord(_ session: WorkSession) throws -> CKRecord {
        let record = CKRecord(recordType: "WorkSession", recordID: CKRecord.ID(recordName: session.id.uuidString))
        record["payload"] = try payloadEncoder.encode(session)
        record["modifiedAt"] = session.modifiedAt
        return record
    }

    private func serverSettingsRecord(_ settings: WorkplaceSettings) throws -> CKRecord {
        let record = CKRecord(recordType: "WorkplaceSettings", recordID: CKRecord.ID(recordName: "workplace-settings"))
        record["payload"] = try payloadEncoder.encode(settings)
        record["modifiedAt"] = settings.modifiedAt
        return record
    }

    private func serverRecordChangedError(serverRecord: CKRecord?) -> CKError {
        var userInfo: [String: Any] = [:]
        if let serverRecord {
            userInfo[CKRecordChangedErrorServerRecordKey] = serverRecord
        }
        return CKError(.serverRecordChanged, userInfo: userInfo)
    }

    // MARK: - Session conflicts

    func testResolveSessionConflictNewerIntendedWins() throws {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        var intended = TestData.session(day: 1, id: id, modifiedAt: newer)
        intended.notes = "intended"
        var server = TestData.session(day: 1, id: id, modifiedAt: older)
        server.notes = "server"

        let error = serverRecordChangedError(serverRecord: try serverSessionRecord(server))
        let resolved = try manager.resolveSessionConflict(intended: intended, error: error)

        let data = try XCTUnwrap(resolved["payload"] as? Data)
        let winner = try payloadDecoder.decode(WorkSession.self, from: data)

        XCTAssertEqual(winner.notes, "intended")
        XCTAssertEqual(resolved["modifiedAt"] as? Date, newer)
    }

    func testResolveSessionConflictNewerServerWins() throws {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        var intended = TestData.session(day: 1, id: id, modifiedAt: older)
        intended.notes = "intended"
        var server = TestData.session(day: 1, id: id, modifiedAt: newer)
        server.notes = "server"

        let error = serverRecordChangedError(serverRecord: try serverSessionRecord(server))
        let resolved = try manager.resolveSessionConflict(intended: intended, error: error)

        let data = try XCTUnwrap(resolved["payload"] as? Data)
        let winner = try payloadDecoder.decode(WorkSession.self, from: data)

        XCTAssertEqual(winner.notes, "server")
        XCTAssertEqual(resolved["modifiedAt"] as? Date, newer)
    }

    func testResolveSessionConflictFallsBackWhenNoServerRecord() throws {
        // iso8601 encoding truncates sub-second precision, so use a whole-second
        // timestamp to keep the round-tripped decode comparable to `intended`.
        let intended = TestData.session(day: 1, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let error = serverRecordChangedError(serverRecord: nil)

        let resolved = try manager.resolveSessionConflict(intended: intended, error: error)

        XCTAssertEqual(resolved.recordType, "WorkSession")
        XCTAssertEqual(resolved.recordID.recordName, intended.id.uuidString)
        let data = try XCTUnwrap(resolved["payload"] as? Data)
        let decoded = try payloadDecoder.decode(WorkSession.self, from: data)
        XCTAssertEqual(decoded, intended)
        XCTAssertEqual(resolved["modifiedAt"] as? Date, intended.modifiedAt)
    }

    // MARK: - Settings conflicts

    func testResolveSettingsConflictNewerIntendedWins() throws {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        var intended = TestData.settings()
        intended.workplaceName = "Intended"
        intended.workerIDNumber = "local-id"
        intended.modifiedAt = newer

        var server = TestData.settings()
        server.workplaceName = "Server"
        server.workerIDNumber = "remote-id"
        server.modifiedAt = older

        let error = serverRecordChangedError(serverRecord: try serverSettingsRecord(server))
        let resolved = try manager.resolveSettingsConflict(intended: intended, error: error)

        let data = try XCTUnwrap(resolved["payload"] as? Data)
        let winner = try payloadDecoder.decode(WorkplaceSettings.self, from: data)

        XCTAssertEqual(winner.workplaceName, "Intended")
        XCTAssertEqual(winner.workerIDNumber, "", "National ID must never be uploaded, regardless of which side wins")
        XCTAssertEqual(resolved["modifiedAt"] as? Date, newer)
    }

    func testResolveSettingsConflictNewerServerWinsButNationalIDStaysBlank() throws {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        var intended = TestData.settings()
        intended.workplaceName = "Intended"
        intended.workerIDNumber = "local-id"
        intended.modifiedAt = older

        var server = TestData.settings()
        server.workplaceName = "Server"
        server.workerIDNumber = "remote-id"
        server.modifiedAt = newer

        let error = serverRecordChangedError(serverRecord: try serverSettingsRecord(server))
        let resolved = try manager.resolveSettingsConflict(intended: intended, error: error)

        let data = try XCTUnwrap(resolved["payload"] as? Data)
        let winner = try payloadDecoder.decode(WorkplaceSettings.self, from: data)

        // Non-ID fields come from the server since it has the newer modifiedAt...
        XCTAssertEqual(winner.workplaceName, "Server")
        // ...but the encoded payload's workerIDNumber is always sanitized to ""
        // (makeSettingsRecord's convention), never leaking either side's national ID.
        XCTAssertEqual(winner.workerIDNumber, "")
        // The record's modifiedAt tracks whichever side actually won the comparison.
        XCTAssertEqual(resolved["modifiedAt"] as? Date, newer)
    }

    func testResolveSettingsConflictFallsBackWhenNoServerRecord() throws {
        var intended = TestData.settings()
        intended.workerIDNumber = "local-id"
        let error = serverRecordChangedError(serverRecord: nil)

        let resolved = try manager.resolveSettingsConflict(intended: intended, error: error)

        XCTAssertEqual(resolved.recordType, "WorkplaceSettings")
        XCTAssertEqual(resolved.recordID.recordName, "workplace-settings")
        let data = try XCTUnwrap(resolved["payload"] as? Data)
        let decoded = try payloadDecoder.decode(WorkplaceSettings.self, from: data)
        XCTAssertEqual(decoded.workplaceName, intended.workplaceName)
        XCTAssertEqual(decoded.workerIDNumber, "", "makeSettingsRecord always strips the national ID before upload")
        XCTAssertEqual(resolved["modifiedAt"] as? Date, intended.modifiedAt)
    }
}
