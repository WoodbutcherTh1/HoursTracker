import XCTest
@testable import HoursTracker

final class CorruptFileQuarantineTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorruptQuarantine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    func testQuarantineMovesFileToCorruptSibling() throws {
        let url = directory.appendingPathComponent("work_sessions.json")
        try Data("not-json".utf8).write(to: url, options: .atomic)

        let quarantined = try XCTUnwrap(
            CorruptFileQuarantine.quarantine(at: url, fileManager: .default)
        )

        XCTAssertEqual(quarantined.lastPathComponent, "work_sessions.json.corrupt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantined.path))
        XCTAssertEqual(try String(contentsOf: quarantined, encoding: .utf8), "not-json")
    }

    func testPersistenceLoadQuarantinesCorruptSessions() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        try Data("{broken".utf8).write(to: sessionsURL, options: .atomic)

        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            documentsDirectory: directory
        )
        let loaded = store.loadSessions()
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionsURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sessionsURL.appendingPathExtension("corrupt").path
            )
        )
    }

    func testPersistenceLoadRetriesTransientFailuresAndDoesNotQuarantine() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        // Write a *valid* payload so a genuine read would succeed. The scripted
        // reader below will fail the first two attempts and only then hand back
        // the real bytes, simulating a Data-Protection lock that clears mid-load.
        let realSessions: [WorkSession] = [
            TestData.session(day: 5, inHour: 8, outHour: 16)
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(realSessions).write(to: sessionsURL, options: .atomic)

        let reader = ScriptedDataReader(
            failures: Array(
                repeating: NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoPermissionError
                ),
                count: 2
            )
        )
        var sleepCalls: [TimeInterval] = []
        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            dataReader: reader,
            documentsDirectory: directory,
            loadRetryAttempts: 3,
            loadRetryBaseDelay: 0,
            sleeper: { sleepCalls.append($0) }
        )

        let loaded = store.loadSessions()

        XCTAssertEqual(loaded.count, 1, "load must recover the intact file after transient retries")
        XCTAssertEqual(reader.attempts, 3, "reader should have been invoked once per attempt")
        XCTAssertEqual(sleepCalls.count, 2, "must back off between the failed attempts, not after success")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sessionsURL.path),
            "transient failures must never move the primary file"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionsURL.appendingPathExtension("corrupt").path
            ),
            "transient read failures must NOT produce a .corrupt sidecar"
        )
    }

    func testPersistenceLoadDoesNotQuarantineWhenTransientRetriesExhaust() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        // A real, valid file exists — but every read attempt fails transiently.
        // The critical invariant: we must return an empty load WITHOUT wiping.
        try Data("[]".utf8).write(to: sessionsURL, options: .atomic)

        let transientError = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EBUSY)
        )
        let reader = ScriptedDataReader(
            failures: Array(repeating: transientError, count: 10)
        )
        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            dataReader: reader,
            documentsDirectory: directory,
            loadRetryAttempts: 3,
            loadRetryBaseDelay: 0,
            sleeper: { _ in }
        )

        let loaded = store.loadSessions()

        XCTAssertTrue(loaded.isEmpty, "exhausted retries should surface as an empty load")
        XCTAssertEqual(reader.attempts, 3, "should stop after the configured retry budget")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sessionsURL.path),
            "exhausted transient retries must leave the file intact for recovery"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionsURL.appendingPathExtension("corrupt").path
            ),
            "exhausted transient retries must never quarantine"
        )
    }

    func testPersistenceLoadDoesNotQuarantineOnNonTransientReadFailure() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        try Data("[]".utf8).write(to: sessionsURL, options: .atomic)

        // A domain we don't recognize as transient — must bail immediately
        // without retries and without quarantining.
        let opaqueError = NSError(domain: "com.example.opaque", code: -1)
        let reader = ScriptedDataReader(
            failures: Array(repeating: opaqueError, count: 10)
        )
        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            dataReader: reader,
            documentsDirectory: directory,
            loadRetryAttempts: 3,
            loadRetryBaseDelay: 0,
            sleeper: { _ in }
        )

        let loaded = store.loadSessions()

        XCTAssertTrue(loaded.isEmpty)
        XCTAssertEqual(reader.attempts, 1, "non-transient errors should not be retried")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionsURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionsURL.appendingPathExtension("corrupt").path
            )
        )
    }

    func testPersistenceLoadStillQuarantinesOnDecodeFailureAfterSuccessfulRead() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        // Bytes are readable but malformed — this is the *only* category that
        // should trigger quarantine.
        try Data("{not-valid-json".utf8).write(to: sessionsURL, options: .atomic)

        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            documentsDirectory: directory,
            loadRetryAttempts: 3,
            loadRetryBaseDelay: 0,
            sleeper: { _ in }
        )

        let loaded = store.loadSessions()
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionsURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sessionsURL.appendingPathExtension("corrupt").path
            )
        )
    }

    func testIsTransientReadErrorClassification() {
        XCTAssertTrue(PersistenceManager.isTransientReadError(
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        ))
        XCTAssertTrue(PersistenceManager.isTransientReadError(
            NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        ))
        XCTAssertTrue(PersistenceManager.isTransientReadError(
            NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))
        ))

        // Outer domain is opaque but the underlying is transient — must still
        // recurse via NSUnderlyingErrorKey and classify as transient.
        let wrapped = NSError(
            domain: "com.example.opaque",
            code: -1,
            userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EAGAIN))
            ]
        )
        XCTAssertTrue(PersistenceManager.isTransientReadError(wrapped))

        // NoSuchFile / unknown domains are NOT transient.
        XCTAssertFalse(PersistenceManager.isTransientReadError(
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        ))
        XCTAssertFalse(PersistenceManager.isTransientReadError(
            NSError(domain: "com.example.other", code: 42)
        ))
    }

    // MARK: - Result-based load API

    /// Follow-up guard for the silent-wipe path: even though the legacy
    /// `loadSessions()` returns `[]` for compatibility, the Result variant
    /// must signal `.temporarilyUnavailable` so `AppViewModel` will refuse to
    /// persist an empty array over the intact file.
    func testLoadSessionsResultReturnsTemporarilyUnavailableWhenRetriesExhaust() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        try Data("[]".utf8).write(to: sessionsURL, options: .atomic)

        let transientError = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EBUSY)
        )
        let reader = ScriptedDataReader(
            failures: Array(repeating: transientError, count: 10)
        )
        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            dataReader: reader,
            documentsDirectory: directory,
            loadRetryAttempts: 3,
            loadRetryBaseDelay: 0,
            sleeper: { _ in }
        )

        let outcome = store.loadSessionsResult()

        guard case .temporarilyUnavailable = outcome else {
            return XCTFail("expected .temporarilyUnavailable, got \(outcome)")
        }
        XCTAssertEqual(reader.attempts, 3, "should stop after the configured retry budget")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sessionsURL.path),
            "exhausted transient retries must leave the file intact"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionsURL.appendingPathExtension("corrupt").path
            ),
            "exhausted transient retries must never quarantine"
        )
    }

    /// Non-transient read errors on an existing file are ALSO unrecoverable at
    /// load time and must NOT be laundered into `.loaded([])` — otherwise a
    /// caller who wrote through the compat API would still wipe the file on
    /// the next save.
    func testLoadSessionsResultReturnsTemporarilyUnavailableOnNonTransientReadFailure() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        try Data("[]".utf8).write(to: sessionsURL, options: .atomic)

        let opaqueError = NSError(domain: "com.example.opaque", code: -1)
        let reader = ScriptedDataReader(failures: [opaqueError])
        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            dataReader: reader,
            documentsDirectory: directory,
            loadRetryAttempts: 3,
            loadRetryBaseDelay: 0,
            sleeper: { _ in }
        )

        let outcome = store.loadSessionsResult()

        guard case .temporarilyUnavailable = outcome else {
            return XCTFail("expected .temporarilyUnavailable, got \(outcome)")
        }
        XCTAssertEqual(reader.attempts, 1, "non-transient errors should not be retried")
    }

    func testLoadSessionsResultReturnsMissingWhenFileAbsent() {
        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            documentsDirectory: directory
        )
        guard case .missing = store.loadSessionsResult() else {
            return XCTFail("expected .missing when sessions file has never been written")
        }
    }

    func testLoadSessionsResultQuarantinesAndReturnsCorruptOnDecodeFailure() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        try Data("{not-valid-json".utf8).write(to: sessionsURL, options: .atomic)

        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            documentsDirectory: directory,
            loadRetryAttempts: 3,
            loadRetryBaseDelay: 0,
            sleeper: { _ in }
        )

        guard case .corruptQuarantined = store.loadSessionsResult() else {
            return XCTFail("decode failure must surface as .corruptQuarantined")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionsURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sessionsURL.appendingPathExtension("corrupt").path
            )
        )
    }

    func testLoadSessionsResultLoadsValidPayload() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        let real: [WorkSession] = [
            TestData.session(day: 7, inHour: 9, outHour: 17)
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(real).write(to: sessionsURL, options: .atomic)

        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            documentsDirectory: directory
        )
        guard case .loaded(let loaded) = store.loadSessionsResult() else {
            return XCTFail("expected .loaded for an intact, valid sessions file")
        }
        XCTAssertEqual(loaded.map(\.id), real.map(\.id))
    }

    func testRemoveSidecarsDeletesQuarantineFiles() throws {
        let url = directory.appendingPathComponent("workplace_settings.json")
        let corrupt = url.appendingPathExtension("corrupt")
        try Data("{}".utf8).write(to: corrupt, options: .atomic)

        CorruptFileQuarantine.removeSidecars(for: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.path))
    }
}
