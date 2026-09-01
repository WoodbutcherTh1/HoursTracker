import XCTest
@testable import HoursTracker

@MainActor
final class AppViewModelTests: XCTestCase {
    private func makeViewModel(
        sessions: [WorkSession] = [],
        store: InMemoryStore = InMemoryStore()
    ) -> (viewModel: AppViewModel, store: InMemoryStore) {
        store.storedSessions = sessions
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())
        return (viewModel, store)
    }

    private func openSessionYesterday() -> WorkSession {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        return WorkSession(
            date: calendar.startOfDay(for: yesterday),
            clockIn: calendar.date(bySettingHour: 20, minute: 0, second: 0, of: yesterday)!,
            clockOut: nil
        )
    }

    func testClockInCreatesOpenSessionAndPersists() {
        let (viewModel, store) = makeViewModel()

        viewModel.clockIn()

        XCTAssertTrue(viewModel.isClockedIn)
        XCTAssertEqual(store.storedSessions.count, 1)
        XCTAssertTrue(store.storedSessions[0].isOpen)
    }

    func testClockInAtCustomTimePersistsOpenSession() {
        let (viewModel, store) = makeViewModel()
        let calendar = Calendar.current
        // A relative offset rather than a fixed wall-clock hour: `clockIn(at:)` clamps to
        // `min(date, Date())`, so an absolute "08:15 today" is only reliably in the past
        // when the test happens to run after 08:15 in the runner's time zone — CI running
        // earlier than that clamps the recorded time to "now" and this test's exact-match
        // assertion below fails on a totally correct clamp, not a real bug. An hour before
        // whenever the test actually runs is in the past unconditionally.
        let arrival = Date().addingTimeInterval(-3600)
        let today = calendar.startOfDay(for: arrival)

        viewModel.clockIn(at: arrival, isManual: true)

        XCTAssertTrue(viewModel.isClockedIn)
        XCTAssertEqual(store.storedSessions.count, 1)
        let session = store.storedSessions[0]
        XCTAssertTrue(session.isOpen)
        XCTAssertTrue(session.isManualEntry)
        XCTAssertEqual(session.clockIn.timeIntervalSince1970, arrival.timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(calendar.isDate(session.date, inSameDayAs: today))
    }

    func testClockInAtFutureTimeIsClampedToNow() {
        let (viewModel, store) = makeViewModel()
        let future = Date().addingTimeInterval(3600)

        let before = Date()
        viewModel.clockIn(at: future)
        let after = Date()

        let clockIn = store.storedSessions[0].clockIn
        XCTAssertGreaterThanOrEqual(clockIn.timeIntervalSince1970, before.timeIntervalSince1970 - 1)
        XCTAssertLessThanOrEqual(clockIn.timeIntervalSince1970, after.timeIntervalSince1970 + 1)
    }

    func testShouldOfferForgotClockInRequiresGracePastTypicalStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14))! // Tuesday
        let settings = WorkplaceSettings.default // rest day Saturday

        let tooEarly = calendar.date(bySettingHour: 8, minute: 10, second: 0, of: day)!
        XCTAssertFalse(
            AppViewModel.shouldOfferForgotClockIn(
                now: tooEarly,
                sessions: [],
                settings: settings,
                calendar: calendar
            )
        )

        let afterGrace = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: day)!
        XCTAssertTrue(
            AppViewModel.shouldOfferForgotClockIn(
                now: afterGrace,
                sessions: [],
                settings: settings,
                calendar: calendar
            )
        )
    }

    func testShouldOfferForgotClockInHiddenWhenOpenOrCompletedOrRestDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14))! // Tuesday
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        let settings = WorkplaceSettings.default
        let lateMorning = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!

        let open = WorkSession(
            date: calendar.startOfDay(for: day),
            clockIn: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day)!,
            clockOut: nil
        )
        XCTAssertFalse(
            AppViewModel.shouldOfferForgotClockIn(
                now: lateMorning,
                sessions: [open],
                settings: settings,
                calendar: calendar
            )
        )

        let completed = WorkSession(
            date: calendar.startOfDay(for: day),
            clockIn: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day)!,
            clockOut: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        )
        XCTAssertFalse(
            AppViewModel.shouldOfferForgotClockIn(
                now: lateMorning,
                sessions: [completed],
                settings: settings,
                calendar: calendar
            )
        )

        let saturdayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: saturday)!
        XCTAssertFalse(
            AppViewModel.shouldOfferForgotClockIn(
                now: saturdayNoon,
                sessions: [],
                settings: settings,
                calendar: calendar
            )
        )
    }

    /// A night-shift worker's typical start (e.g. 22:00) must drive the prompt,
    /// not the old hardcoded 08:00 — otherwise they'd get nagged every morning
    /// before they've even started their shift.
    func testShouldOfferForgotClockInUsesConfiguredNightShiftStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14))! // Tuesday
        var settings = WorkplaceSettings.default
        settings.expectedShiftStartHour = 22
        settings.expectedShiftStartMinute = 0

        let morning = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: day)!
        XCTAssertFalse(
            AppViewModel.shouldOfferForgotClockIn(
                now: morning,
                sessions: [],
                settings: settings,
                calendar: calendar
            )
        )

        let afterNightGrace = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: day)!
        XCTAssertTrue(
            AppViewModel.shouldOfferForgotClockIn(
                now: afterNightGrace,
                sessions: [],
                settings: settings,
                calendar: calendar
            )
        )
    }

    func testSecondClockInSameDayAfterClockOutIsAllowed() {
        let (viewModel, _) = makeViewModel()

        viewModel.clockIn()
        viewModel.clockOut()
        viewModel.clockIn()

        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertTrue(viewModel.isClockedIn)
    }

    func testClockOutClosesSessionAndShowsSummary() {
        let (viewModel, store) = makeViewModel()

        viewModel.clockIn()
        viewModel.clockOut()

        XCTAssertFalse(viewModel.isClockedIn)
        XCTAssertNotNil(viewModel.lastCompletedBreakdown)
        XCTAssertNotNil(viewModel.lastCompletedSessionID)
        XCTAssertEqual(viewModel.lastCompletedSessionID, store.storedSessions[0].id)
        XCTAssertTrue(viewModel.showDaySummary)
        XCTAssertFalse(store.storedSessions[0].isOpen)
    }

    func testSecondShiftSummaryIsForThatShiftOnly() throws {
        let day = Calendar.current.startOfDay(for: Date())
        // Morning shift already completed: 8 hours.
        let morning = WorkSession(
            date: day,
            clockIn: day.addingTimeInterval(8 * 3600),
            clockOut: day.addingTimeInterval(16 * 3600)
        )
        let (viewModel, _) = makeViewModel(sessions: [morning])

        viewModel.clockIn()
        viewModel.clockOut()

        let completedID = try XCTUnwrap(viewModel.lastCompletedSessionID)
        XCTAssertNotEqual(completedID, morning.id)
        let summary = try XCTUnwrap(viewModel.lastCompletedBreakdown)
        let justClosed = try XCTUnwrap(viewModel.sessions.first { $0.id == completedID })

        // Summary matches the just-closed shift, not the whole day (~8h+).
        XCTAssertEqual(summary.totalHours, justClosed.effectiveHours, accuracy: 0.05)
        XCTAssertLessThan(summary.totalHours, 1.0)

        let dayTotal = OvertimeCalculator.aggregate(
            sessions: viewModel.sessions.filter { !$0.isOpen },
            settings: viewModel.settings
        )
        XCTAssertGreaterThan(dayTotal.totalHours, 7.0)
        XCTAssertNotEqual(summary.totalHours, dayTotal.totalHours, accuracy: 0.5)
    }

    func testDeleteLastCompletedSessionRemovesOnlyThatShift() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let earlier = WorkSession(
            date: day,
            clockIn: day.addingTimeInterval(8 * 3600),
            clockOut: day.addingTimeInterval(12 * 3600)
        )
        let (viewModel, store) = makeViewModel(sessions: [earlier])

        viewModel.clockIn()
        viewModel.clockOut()

        let completedID = try XCTUnwrap(viewModel.lastCompletedSessionID)
        XCTAssertNotEqual(completedID, earlier.id)
        XCTAssertEqual(viewModel.sessions.count, 2)

        let justCompleted = try XCTUnwrap(viewModel.sessions.first { $0.id == completedID })
        viewModel.deleteSession(justCompleted)
        viewModel.dismissDaySummary()

        XCTAssertEqual(viewModel.sessions.map(\.id), [earlier.id])
        XCTAssertEqual(store.storedSessions.map(\.id), [earlier.id])
        XCTAssertNil(viewModel.lastCompletedSessionID)
        XCTAssertFalse(viewModel.showDaySummary)
    }

    func testSessionOpenSinceYesterdayIsStillActive() {
        let yesterdaysSession = openSessionYesterday()
        let (viewModel, _) = makeViewModel(sessions: [yesterdaysSession])

        XCTAssertEqual(viewModel.activeSession?.id, yesterdaysSession.id)
        XCTAssertTrue(viewModel.isClockedIn)
    }

    func testClockInBlockedWhileYesterdaysSessionIsOpen() {
        let yesterdaysSession = openSessionYesterday()
        let (viewModel, _) = makeViewModel(sessions: [yesterdaysSession])

        XCTAssertFalse(viewModel.canClockInToday)
        viewModel.clockIn()

        XCTAssertEqual(viewModel.sessions.count, 1)
    }

    func testClockOutClosesYesterdaysOpenSession() {
        let yesterdaysSession = openSessionYesterday()
        let (viewModel, store) = makeViewModel(sessions: [yesterdaysSession])

        viewModel.clockOut()

        XCTAssertFalse(viewModel.isClockedIn)
        XCTAssertFalse(store.storedSessions[0].isOpen)
    }

    func testManualSessionAllowsMultipleShiftsSameDay() {
        let (viewModel, _) = makeViewModel()
        let day = TestData.date(2026, 3, 10)

        viewModel.addManualSession(
            date: day,
            clockIn: TestData.date(2026, 3, 10, 8),
            clockOut: TestData.date(2026, 3, 10, 12),
            notes: nil
        )
        viewModel.addManualSession(
            date: day,
            clockIn: TestData.date(2026, 3, 10, 14),
            clockOut: TestData.date(2026, 3, 10, 18),
            notes: nil
        )

        XCTAssertEqual(viewModel.sessions.count, 2)
    }

    func testDeleteSessionPersists() {
        let session = TestData.session(day: 1)
        let (viewModel, store) = makeViewModel(sessions: [session])

        viewModel.deleteSession(session)

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertTrue(store.storedSessions.isEmpty)
    }

    func testSaveFailureSurfacesErrorMessage() {
        let store = InMemoryStore()
        let (viewModel, _) = makeViewModel(store: store)
        store.saveError = NSError(domain: "test", code: 1)

        viewModel.clockIn()

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSaveSettingsFailureSurfacesErrorMessage() {
        let store = InMemoryStore()
        let (viewModel, _) = makeViewModel(store: store)
        store.saveError = NSError(domain: "test", code: 1)

        viewModel.saveSettings(TestData.settings())

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testDeleteAllUserDataClearsLocalStateAndUsesLocalSettingsSave() async {
        let session = TestData.session(day: 1)
        let store = InMemoryStore()
        store.isCloudSyncSupported = true
        store.storedSessions = [session]
        store.storedSettings = TestData.settings()
        let location = MockLocationReminderManager()
        let viewModel = AppViewModel(store: store, locationManager: location)

        let exportURL = try? ExportTempFileStore.write(
            data: Data("leftover".utf8),
            fileName: "HoursReport-delete-all.txt"
        )

        viewModel.deleteAllUserData()

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertEqual(viewModel.settings.workerIDNumber, "")
        XCTAssertEqual(viewModel.settings.workplaceName, "")
        XCTAssertEqual(viewModel.settings.hourlyRate, WorkplaceSettings.default.hourlyRate)
        XCTAssertEqual(store.saveSettingsLocallyCallCount, 1)
        XCTAssertEqual(location.stopReminderCalls, 1)
        if let exportURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
        }

        let deadline = Date().addingTimeInterval(2)
        while store.purgeCloudCallCount == 0, Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(store.purgeCloudCallCount, 1)
        XCTAssertEqual(store.lastPurgedSessionIDs, [session.id])
    }

    // MARK: - Silent-wipe regression (transient load failure)

    /// After a transient load failure of an existing sessions file, the
    /// view-model must NOT persist its (empty) in-memory `sessions` back to
    /// the store — that would silently wipe the intact-but-unreadable file
    /// once Data Protection released the class key.
    func testTransientSessionsLoadFailureDoesNotWipeStoreOnNextMutation() {
        let real = TestData.session(day: 10, inHour: 8, outHour: 16)
        let store = InMemoryStore()
        store.storedSessions = [real]
        // Store *reports* the sessions file as intact-but-unreadable, but the
        // authoritative `storedSessions` above stays populated so we can prove
        // the wipe path is closed: the view-model must NOT overwrite it.
        store.sessionsLoadResultOverride = .temporarilyUnavailable

        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        // In-memory did NOT invent a populated store; it stayed empty because
        // the load was unavailable, not because the file is empty.
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage, "unavailable load should surface an error to the user")

        // The critical invariant: any mutation that would normally call
        // `persist()` must NOT hand `[]` (or any partial state) to
        // `store.saveSessions`, because the real bytes are still on disk.
        viewModel.clockIn()

        XCTAssertEqual(
            store.storedSessions.map(\.id),
            [real.id],
            "transient load failure must not lead to overwriting the intact sessions file"
        )
    }

    /// Same guarantee for a plain mutation flow: deleting an (in-memory-empty)
    /// session list after a transient load must not overwrite the on-disk file.
    func testTransientSessionsLoadFailureBlocksDeletePersist() {
        let real = TestData.session(day: 11, inHour: 9, outHour: 17)
        let store = InMemoryStore()
        store.storedSessions = [real]
        store.sessionsLoadResultOverride = .temporarilyUnavailable
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        viewModel.deleteSession(real)

        XCTAssertEqual(
            store.storedSessions.map(\.id),
            [real.id],
            "deletion of an unloaded session must not clobber the real file"
        )
    }

    /// `retryLoadIfNeeded()` is the recovery half of the guarantee above: once
    /// the transient failure clears (e.g. the device actually unlocks), the
    /// app must pick up the real on-disk data again on its own — without
    /// this, the UI would show an empty history for the rest of the process's
    /// life even though the file was never touched.
    func testRetryLoadIfNeededRecoversAfterTransientFailureClears() {
        let real = TestData.session(day: 12, inHour: 8, outHour: 16)
        let store = InMemoryStore()
        store.storedSessions = [real]
        store.sessionsLoadResultOverride = .temporarilyUnavailable

        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())
        XCTAssertTrue(viewModel.sessions.isEmpty, "load should not fabricate an empty store while unavailable")

        // The underlying condition clears (e.g. Data Protection released the
        // class key after the user actually unlocked the device).
        store.sessionsLoadResultOverride = nil
        viewModel.retryLoadIfNeeded()

        XCTAssertEqual(
            viewModel.sessions.map(\.id),
            [real.id],
            "recovering from a transient failure must reload the real sessions, not leave the UI stuck empty"
        )

        // And normal persistence is unblocked again.
        viewModel.clockIn()
        XCTAssertEqual(store.storedSessions.count, 2)
    }

    /// A call to `retryLoadIfNeeded()` when nothing is wrong must be a no-op
    /// (it must not re-read the store and risk clobbering in-memory state).
    func testRetryLoadIfNeededIsNoOpWhenLoadWasFine() {
        let real = TestData.session(day: 13, inHour: 8, outHour: 16)
        let store = InMemoryStore()
        store.storedSessions = [real]
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        // Simulate an in-memory-only change that hasn't been reflected back
        // into `store.storedSessions` the way a real save would.
        store.storedSessions = []
        viewModel.retryLoadIfNeeded()

        XCTAssertEqual(
            viewModel.sessions.map(\.id),
            [real.id],
            "retryLoadIfNeeded must not re-read the store when the prior load was not flagged unavailable"
        )
    }

    /// Settings save must be blocked on the same principle.
    func testTransientSettingsLoadFailureDoesNotWipeSettings() {
        let real = TestData.settings(hourlyRate: 250)
        let store = InMemoryStore()
        store.storedSettings = real
        store.settingsLoadResultOverride = .temporarilyUnavailable
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.saveSettings(WorkplaceSettings.default)

        XCTAssertEqual(
            store.storedSettings.hourlyRate,
            250,
            "transient settings load failure must not wipe the intact settings file"
        )
    }

    /// `.corruptQuarantined` is different from `.temporarilyUnavailable`:
    /// bytes were readable but did not decode, so the file has already been
    /// moved aside. Saving fresh state over the (now-empty) primary path is
    /// safe and desirable.
    func testCorruptSessionsLoadStillAllowsPersist() {
        let store = InMemoryStore()
        store.storedSessions = []
        store.sessionsLoadResultOverride = .corruptQuarantined
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        XCTAssertTrue(viewModel.sessions.isEmpty)

        viewModel.clockIn()

        XCTAssertEqual(
            store.storedSessions.count,
            1,
            "corrupt-quarantined load has no intact bytes to protect — save must proceed"
        )
    }

    func testDeleteAllUserDataSurfacesCloudPurgeFailure() async {
        let store = InMemoryStore()
        store.isCloudSyncSupported = true
        store.purgeCloudError = NSError(domain: "test", code: 99)
        store.storedSessions = [TestData.session(day: 2)]
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        viewModel.deleteAllUserData()

        let deadline = Date().addingTimeInterval(2)
        while viewModel.errorMessage == nil, Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.errorMessage, L10n.privacyDeleteCloudPartialFailure)
    }

    // MARK: - Concurrency / overlap guards

    /// Regression: an OCR import whose overwrite confirmation includes today
    /// must never delete or replace the active ongoing shift.
    func testImportScannedSessions_doesNotOverwriteActiveShift() {
        let store = InMemoryStore()
        let calendar = Calendar.current
        let vm = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        // Clock in to start an active ongoing session.
        vm.clockIn()
        let openSession = vm.activeSession
        XCTAssertNotNil(openSession)

        // Import with overwriteDays containing today's date.
        let today = calendar.startOfDay(for: Date())
        let draft = ScannedSessionDraft(
            date: today,
            clockIn: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: today)!,
            clockOut: calendar.date(bySettingHour: 16, minute: 30, second: 0, of: today)!
        )
        let imported = vm.importScannedSessions([draft], overwriteDays: [today])

        // The active session remains intact and is still present/open.
        XCTAssertEqual(imported, 0)
        XCTAssertEqual(vm.activeSession?.id, openSession?.id)
        XCTAssertTrue(vm.sessions.contains { $0.id == openSession?.id && $0.isOpen })
        XCTAssertEqual(vm.sessions.map(\.id), [openSession?.id ?? UUID()])
        XCTAssertEqual(store.storedSessions.map(\.id), [openSession?.id ?? UUID()])
    }

    func testRapidDoubleClockInCreatesExactlyOneOpenSession() {
        let (viewModel, store) = makeViewModel()

        // Simulates a rapid double-tap on the clock-in button: both calls run
        // back to back on the main actor. The second must be a no-op.
        viewModel.clockIn()
        viewModel.clockIn()

        XCTAssertEqual(viewModel.sessions.count, 1, "duplicate clock-in must be blocked")
        XCTAssertEqual(store.storedSessions.count, 1)
        XCTAssertTrue(viewModel.sessions[0].isOpen)
    }

    func testClockOutTwiceDoesNotDuplicateOrCorruptState() {
        let (viewModel, store) = makeViewModel()
        viewModel.clockIn()

        viewModel.clockOut()
        let firstCount = viewModel.sessions.count
        let firstIDs = Set(viewModel.sessions.map(\.id))

        // Second clock-out: there is no open session anymore, so it's a no-op.
        viewModel.clockOut()

        XCTAssertEqual(viewModel.sessions.count, firstCount)
        XCTAssertEqual(Set(viewModel.sessions.map(\.id)), firstIDs)
        XCTAssertFalse(viewModel.sessions[0].isOpen)
        XCTAssertEqual(store.storedSessions.count, 1)
    }

    func testDeleteSessionTwiceIsIdempotent() {
        let (viewModel, store) = makeViewModel()
        viewModel.clockIn()
        let session = viewModel.activeSession!

        viewModel.deleteSession(session)
        viewModel.deleteSession(session)

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertTrue(store.storedSessions.isEmpty)
    }

    func testConcurrentManualEntriesAllPersistWithDistinctIDs() {
        let (viewModel, store) = makeViewModel()
        let calendar = Calendar.current
        let day = TestData.date(2026, 3, 10)

        // Multiple completed shifts added in quick succession on the same day
        // are all allowed and all survive the persist path.
        for hour in [8, 12, 16] {
            viewModel.addManualSession(
                date: day,
                clockIn: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!,
                clockOut: calendar.date(bySettingHour: hour + 3, minute: 0, second: 0, of: day)!,
                notes: nil
            )
        }

        XCTAssertEqual(viewModel.sessions.count, 3)
        XCTAssertEqual(Set(viewModel.sessions.map(\.id)).count, 3)
        XCTAssertEqual(store.storedSessions.count, 3)
    }

    func testImportCannotOverwriteDayWithActiveOngoingShift() {
        let store = InMemoryStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // An ongoing shift started earlier today — this is the active shift.
        let openShift = WorkSession(
            date: today,
            clockIn: Date().addingTimeInterval(-2 * 3600),
            clockOut: nil
        )
        store.storedSessions = [openShift]
        store.storedSettings = TestData.settings()
        let vm = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        XCTAssertTrue(vm.isClockedIn)

        // Even with an explicit overwrite confirmation for that day, the import
        // must not delete or replace the running shift.
        let draft = ScannedSessionDraft(
            date: today,
            clockIn: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: today)!,
            clockOut: calendar.date(bySettingHour: 16, minute: 30, second: 0, of: today)!
        )
        let imported = vm.importScannedSessions([draft], overwriteDays: [today])

        XCTAssertEqual(imported, 0, "import over a live shift must be rejected")
        XCTAssertEqual(vm.sessions.map(\.id), [openShift.id], "active shift must be untouched")
        XCTAssertTrue(vm.isClockedIn)
        XCTAssertEqual(store.storedSessions.map(\.id), [openShift.id])
    }

    func testImportSkipsOnlyTheConflictingDayAndImportsCleanDays() {
        let store = InMemoryStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let openShift = WorkSession(
            date: today,
            clockIn: Date().addingTimeInterval(-2 * 3600),
            clockOut: nil
        )
        store.storedSessions = [openShift]
        store.storedSettings = TestData.settings()
        let vm = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let cleanDraft = ScannedSessionDraft(
            date: yesterday,
            clockIn: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: yesterday)!,
            clockOut: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: yesterday)!
        )
        let conflictDraft = ScannedSessionDraft(
            date: today,
            clockIn: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: today)!,
            clockOut: calendar.date(bySettingHour: 16, minute: 30, second: 0, of: today)!
        )

        let imported = vm.importScannedSessions(
            [cleanDraft, conflictDraft],
            overwriteDays: [today]
        )

        XCTAssertEqual(imported, 1)
        XCTAssertEqual(vm.sessions.count, 2)
        XCTAssertEqual(vm.sessions.first { $0.id == openShift.id }?.clockOut, nil)
        XCTAssertEqual(vm.sessions.filter { $0.id != openShift.id }.first?.date,
                       calendar.startOfDay(for: yesterday))
        XCTAssertEqual(store.storedSessions.count, 2)
    }

    func testCloudWriteQueueSerializesInterleavedTasks() async {
        let queue = CloudWriteQueue()
        actor Counter {
            var value = 0
            var peakConcurrent = 0
            var current = 0
            func enter() {
                current += 1
                peakConcurrent = max(peakConcurrent, current)
                value += 1
            }
            func exit() { current -= 1 }
        }
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await queue.enqueue {
                        await counter.enter()
                        try? await Task.sleep(for: .milliseconds(5))
                        await counter.exit()
                    }
                }
            }
        }

        let value = await counter.value
        let peak = await counter.peakConcurrent
        XCTAssertEqual(value, 20)
        XCTAssertEqual(peak, 1, "CloudWriteQueue tasks must never interleave")
    }
}
