import Foundation
import SwiftUI
import CoreLocation
import UserNotifications
import UIKit

@MainActor
final class AppViewModel: ObservableObject {
    /// The app's single live view model. Shared (rather than owned only by the
    /// SwiftUI scene) so a widget button intent that iOS runs in the background —
    /// with no UI on screen — acts on the same instance the UI shows later.
    static let shared = AppViewModel()

    @Published private(set) var sessions: [WorkSession] = []
    @Published var settings: WorkplaceSettings = .default
    @Published var lastCompletedBreakdown: DayPayBreakdown?
    /// Session that was just clocked out; used by the day-summary sheet to delete only that shift.
    @Published private(set) var lastCompletedSessionID: UUID?
    @Published var showDaySummary = false
    @Published private(set) var syncState: SyncState = .idle
    @Published var errorMessage: String?
    @Published private(set) var successToast: String?
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var areLocationNotificationsDenied = false
    /// Live pay for the open shift — what Home, the Watch, the widgets and the Live
    /// Activity all read, so they show the same figure. Nil when clocked out.
    @Published private(set) var liveCurve: LivePayCurve?
    /// The shift just deleted, while its "Undo" banner is on screen.
    @Published private(set) var undoableDeletion: WorkSession?
    /// Every shift the showing Undo banner restores when it came from a multi-delete.
    private var undoableBulkIDs: [UUID] = []

    /// Background Smart Scanner job — user can dismiss the picker and keep using the app.
    enum ScannerImportPhase: Equatable {
        case idle
        case processing
        case ready
        case failed(String)
    }

    @Published private(set) var scannerImportPhase: ScannerImportPhase = .idle
    @Published private(set) var pendingScannerResult: TimesheetScanResult?
    @Published var showPendingScannerReview = false
    @Published var showAssistant = false
    /// Set by the `hourstracker://action/scan` deep link; MainTabView routes it
    /// into the same single-sheet mechanism the assistant uses.
    @Published var showScannerSheet = false
    /// Set when the paired Watch requests an export — the phone generates the file
    /// (same `ExportManager` pipeline as the Export tab's own button) and Export tab
    /// presents its share sheet for it the next time the app is open, since the Watch
    /// itself cannot present a file share sheet. See `WatchConnectivityManager`.
    @Published var pendingWatchExport: ShareableFile?

    private let store: SyncingStore
    private let locationManager: LocationReminderManaging
    private let exportManager = ExportManager()
    private let locationCapture = LocationCaptureHelper()
    private var successToastTask: Task<Void, Never>?
    private var liveSurfacesTask: Task<Void, Never>?
    /// How many debounced live-surface pushes actually went out, and the gross/net
    /// choice the last one carried (observable by tests).
    private(set) var liveSurfacesPushCount = 0
    private(set) var lastLiveSurfacesShowsNet: Bool?
    private var scannerImportTask: Task<Void, Never>?
    private var liveActivityRefreshTask: Task<Void, Never>?
    /// Inputs `liveCurve` was last built from; it's only rebuilt when they change.
    private var liveCurveInputs: LiveCurveInputs?
    private var undoClearTask: Task<Void, Never>?
    private var accountBackupTask: Task<Void, Never>?
    private let deletedSessions: DeletedSessionsStore
    private let backups: LocalBackupStore

    private struct LiveCurveInputs: Equatable {
        let session: WorkSession
        let settings: WorkplaceSettings
        let sessionCount: Int
    }

    /// Set to `true` when `load()` observed that `sessions.json` exists on disk
    /// but could not be read (e.g. Data Protection race just after unlock).
    /// While `true`, `persist()` refuses to write, because saving the current
    /// (empty) in-memory `sessions` would silently wipe the intact file.
    /// Cleared by any subsequent load or `syncNow` that returns real data.
    private var sessionsLoadUnavailable = false
    /// Same rationale as `sessionsLoadUnavailable`, applied to
    /// `workplace_settings.json` and `persistSettings()`.
    private var settingsLoadUnavailable = false

    /// Hide the Settings sync section when this build has no CloudKit backend.
    var isCloudSyncSupported: Bool { store.isCloudSyncSupported }

    /// User opt-in for private iCloud sync (default off).
    var isICloudSyncEnabled: Bool {
        get { store.isICloudSyncEnabled }
        set { store.isICloudSyncEnabled = newValue }
    }

    func refreshLocationPermissionStatuses() {
        locationAuthorizationStatus = locationManager.authorizationStatus
        locationManager.refreshPermissionStatuses()
        areLocationNotificationsDenied = locationManager.areNotificationsDenied
        // Notification settings arrive asynchronously; re-read shortly after.
        // withAnimation(.none) prevents the deferred @Published updates from
        // inserting/removing conditional location rows inside the tab-transition
        // animation context (~300 ms), which would cause a visible height jump.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.none) {
                areLocationNotificationsDenied = locationManager.areNotificationsDenied
                locationAuthorizationStatus = locationManager.authorizationStatus
            }
        }
    }

    var isSyncing: Bool {
        if case .syncing = syncState { return true }
        return false
    }

    var locationUpdates: Published<CLLocation?>.Publisher {
        locationCapture.$lastLocation
    }

    var locationCaptureErrors: Published<Error?>.Publisher {
        locationCapture.$error
    }

    /// Brief green confirmation for successful user actions (save, delete, import).
    func showSuccessToast(_ message: String) {
        #if DEBUG
        // Screenshot / Design QA runs are "clean": no toasts over the screens.
        if ProcessInfo.processInfo.arguments.contains("UITEST_SCREENSHOTS") { return }
        #endif
        successToastTask?.cancel()
        successToast = message
        successToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if successToast == message {
                successToast = nil
            }
        }
    }

    // MARK: - Smart Scanner background import

    /// Runs OCR + LLM structuring off the pick UI so the user can keep using the app.
    func startScannerImport(image: UIImage) {
        startScannerImport {
            try await TimesheetScannerManager.shared.scan(image: image)
        }
    }

    func startScannerImport(fileURL: URL) {
        startScannerImport {
            try await TimesheetScannerManager.shared.scan(fileURL: fileURL)
        }
    }

    private func startScannerImport(_ work: @escaping @Sendable () async throws -> TimesheetScanResult) {
        scannerImportTask?.cancel()
        pendingScannerResult = nil
        showPendingScannerReview = false
        scannerImportPhase = .processing
        scannerImportTask = Task { @MainActor in
            do {
                let result = try await work()
                guard !Task.isCancelled else { return }
                pendingScannerResult = result
                scannerImportPhase = .ready
                showPendingScannerReview = true
                showSuccessToast(L10n.scannerReadyForReview)
            } catch {
                guard !Task.isCancelled else { return }
                scannerImportPhase = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    func openPendingScannerReview() {
        guard case .ready = scannerImportPhase, pendingScannerResult != nil else { return }
        showPendingScannerReview = true
    }

    func clearScannerImport() {
        scannerImportTask?.cancel()
        scannerImportTask = nil
        pendingScannerResult = nil
        scannerImportPhase = .idle
        showPendingScannerReview = false
    }

    init(
        store: SyncingStore = SyncingPersistenceStore.shared,
        locationManager: LocationReminderManaging = LocationReminderManager.shared,
        deletedSessions: DeletedSessionsStore = .shared,
        backups: LocalBackupStore = .shared
    ) {
        self.store = store
        self.locationManager = locationManager
        self.deletedSessions = deletedSessions
        self.backups = backups
        syncState = store.syncState
        load()
        // An open shift from a previous launch: build its live pay curve right away so
        // Home and the widgets show the shared figure from the first frame.
        refreshLiveCurve()
        takeDailyBackupIfNeeded()
        refreshReminders()
        refreshLocationPermissionStatuses()
        startLiveActivityRefreshLoop()
    }

    deinit {
        liveActivityRefreshTask?.cancel()
    }

    // MARK: - Active Session

    /// The most recent open session, regardless of which day it started on.
    /// A session left open past midnight must stay reachable so it can still
    /// be clocked out from the Home tab.
    var activeSession: WorkSession? {
        sessions
            .filter(\.isOpen)
            .max { $0.clockIn < $1.clockIn }
    }

    var isClockedIn: Bool {
        activeSession != nil
    }

    /// Clock In is available whenever there is no open session (multiple completed
    /// shifts on the same calendar day are allowed).
    var canClockIn: Bool {
        activeSession == nil
    }

    /// Compatibility alias used by older phase-1 tests / call sites.
    var canClockInToday: Bool {
        canClockIn
    }

    // MARK: - Clock In / Out

    /// Start an open shift. `at` defaults to now; pass an earlier time for late / forgotten clock-in.
    /// Arrival is clamped so it cannot be in the future. Uses the same persist + tombstone path
    /// as a normal clock-in (no parallel save route).
    func clockIn(at date: Date = Date(), isManual: Bool = false) {
        guard canClockIn else { return }
        let clockInDate = min(date, Date())
        let session = WorkSession(
            date: Calendar.current.startOfDay(for: clockInDate),
            clockIn: clockInDate,
            clockOut: nil,
            isManualEntry: isManual,
            dayType: resolvedDayType(for: clockInDate)
        )
        sessions.append(session)
        persist()
        refreshReminders()
        // First clock-in is the natural moment to ask for notification access, if
        // it hasn't been asked yet — the clock-out reminder is about to be useful.
        ShiftReminderScheduler.reschedule(sessions: sessions, settings: settings, askPermission: true)
        syncWidget()
        refreshAppShortcuts()
        // Start Live Activity for the running shift.
        if #available(iOS 16.1, *) {
            LiveActivityManager.start(
                session: session,
                settings: settings,
                curve: refreshLiveCurve(),
                showsNet: livePayShowsNet
            )
        }
        ActivityLogStore.shared.log(
            L10n.logEventClockIn,
            level: .success,
            category: "clock",
            details: ISO8601DateFormatter().string(from: clockInDate)
        )
    }

    /// Offer “forgot to clock in?” when:
    /// - there is no open shift,
    /// - there is no completed shift yet today,
    /// - today is not a configured rest day,
    /// - local time is at least `graceMinutes` past the worker's configured
    ///   typical shift start (`settings.expectedShiftStartHour/Minute`) — so a
    ///   night-shift worker whose typical start is e.g. 22:00 isn't nagged at 08:30.
    var shouldOfferForgotClockIn: Bool {
        Self.shouldOfferForgotClockIn(
            now: Date(),
            sessions: sessions,
            settings: settings
        )
    }

    static func shouldOfferForgotClockIn(
        now: Date,
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        calendar: Calendar = .current,
        graceMinutes: Int = 30
    ) -> Bool {
        if sessions.contains(where: \.isOpen) { return false }

        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: now)
        if settings.isRestDayWeekday(weekday) { return false }

        let hasCompletedToday = sessions.contains {
            $0.clockOut != nil && calendar.isDate($0.date, inSameDayAs: today)
        }
        if hasCompletedToday { return false }

        guard
            let typicalStart = calendar.date(
                bySettingHour: settings.expectedShiftStartHour,
                minute: settings.expectedShiftStartMinute,
                second: 0,
                of: today
            )
        else { return false }
        let threshold = typicalStart.addingTimeInterval(TimeInterval(graceMinutes * 60))
        return now >= threshold
    }

    /// `notifySummary: false` when the caller shows the summary itself (Siri speaks it).
    func clockOut(notifySummary: Bool = true) {
        guard let index = sessions.firstIndex(where: { $0.id == activeSession?.id }) else { return }
        // End Live Activity before the session is modified.
        if #available(iOS 16.1, *) {
            LiveActivityManager.end(
                session: sessions[index],
                settings: settings,
                curve: liveCurve,
                showsNet: livePayShowsNet
            )
        }
        let clockOutDate = Date()
        // Clocking out mid-break ends that break at the same moment.
        sessions[index].closeOpenBreak(at: clockOutDate, deductFromPay: !settings.breaksArePaid)
        BreakReminderScheduler.cancel()
        sessions[index].clockOut = clockOutDate
        sessions[index].isNightShift = WorkSession.qualifiesAsNightShift(
            clockIn: sessions[index].clockIn,
            clockOut: clockOutDate
        )
        // Long shifts get the configured unpaid break unless one was set already.
        sessions[index].applyDefaultBreakIfNeeded(settings: settings)
        sessions[index].touch()
        // Summarize only the shift just closed (day-aware so same-day OT/gas
        // sharing stays correct, but totals are for this session alone).
        lastCompletedSessionID = sessions[index].id
        lastCompletedBreakdown = OvertimeCalculator.breakdown(
            for: sessions[index],
            in: sessions,
            settings: settings
        )
        showDaySummary = true
        // Clocked out from the Lock Screen, a widget or the Watch: the Day Summary
        // can't be seen, so send it as a notification instead.
        if notifySummary, UIApplication.shared.applicationState != .active, !AnnouncementCenter.isAutomatedRun,
           let breakdown = lastCompletedBreakdown {
            ShiftSummaryNotifier.post(session: sessions[index], breakdown: breakdown, showsNet: livePayShowsNet)
        }
        persist()
        refreshReminders()
        syncWidget()
        refreshAppShortcuts()
        ActivityLogStore.shared.log(
            L10n.logEventClockOut,
            level: .success,
            category: "clock",
            details: String(format: "%.2fh", sessions[index].totalHours)
        )
    }

    // MARK: - Breaks

    /// True while the open shift has a break in progress.
    var isOnBreak: Bool {
        activeSession?.isOnBreak ?? false
    }

    /// "יצאתי להפסקה": pauses the paid clock and schedules the break reminders.
    func startBreak(at date: Date = Date()) {
        guard let id = activeSession?.id,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let start = min(date, Date())
        guard sessions[index].startBreak(at: start) else { return }
        sessions[index].touch()
        persist()
        syncWidget()
        BreakReminderScheduler.schedule(breakStart: start)
        ActivityLogStore.shared.log(L10n.logEventBreakStart, level: .info, category: "break")
    }

    /// "חזרתי": closes the running break and cancels any pending break reminder.
    func endBreak(at date: Date = Date()) {
        guard let id = activeSession?.id,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard sessions[index].endBreak(at: min(date, Date()), deductFromPay: !settings.breaksArePaid) else { return }
        sessions[index].touch()
        persist()
        syncWidget()
        BreakReminderScheduler.cancel()
        ActivityLogStore.shared.log(
            L10n.logEventBreakEnd,
            level: .info,
            category: "break",
            details: "\(sessions[index].breakMinutes)m"
        )
    }

    func toggleBreak() {
        if isOnBreak {
            endBreak()
        } else {
            startBreak()
        }
    }

    func dismissDaySummary() {
        showDaySummary = false
        lastCompletedBreakdown = nil
        lastCompletedSessionID = nil
        ShiftSummaryNotifier.clear()
    }

    /// Opens the Day Summary for a finished shift — from the "Shift complete"
    /// notification, possibly after the app was relaunched.
    func presentDaySummary(sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }), session.clockOut != nil else { return }
        lastCompletedSessionID = session.id
        lastCompletedBreakdown = OvertimeCalculator.breakdown(for: session, in: sessions, settings: settings)
        showDaySummary = true
    }

    #if DEBUG
    /// Screenshot / Design QA only: open the Day Summary for an existing shift
    /// (e.g. a seeded Shabbat or night shift), exactly as clocking out would.
    func presentDaySummaryForScreenshots(clockIn: Date) {
        guard let session = sessions.first(where: { abs($0.clockIn.timeIntervalSince(clockIn)) < 1 }),
              session.clockOut != nil else { return }
        lastCompletedSessionID = session.id
        lastCompletedBreakdown = OvertimeCalculator.breakdown(for: session, in: sessions, settings: settings)
        showDaySummary = true
    }
    #endif

    /// Day type to use for a new session on `date`, honoring a holiday already
    /// marked that day (e.g. via manual entry) instead of letting an automatic
    /// clock-in or import silently downgrade it back to `.regular`/`.restDay`.
    func resolvedDayType(for date: Date, calendar: Calendar = .current) -> DayType {
        let hasHolidayMarked = sessions.contains {
            $0.dayType == .holiday && calendar.isDate($0.date, inSameDayAs: date)
        }
        if hasHolidayMarked { return .holiday }
        // Bundled Israeli holiday calendar — a statutory rest day overrides the
        // regular rest-day auto-tag (and never downgrades a manual marking).
        if IsraeliHolidayCalendar.isHoliday(date, calendar: calendar) { return .holiday }
        return DayType.automatic(for: date, settings: settings)
    }

    /// What marking `date` as sick would pay, given the worker's existing sick
    /// history — lets the entry UI preview the day-number/percentage live,
    /// before saving.
    func sickStreakPreview(for date: Date, calendar: Calendar = .current) -> (dayNumber: Int, percentage: Double) {
        let day = calendar.startOfDay(for: date)
        var sickDates = Set(sessions.filter { $0.dayType == .sick }.map { calendar.startOfDay(for: $0.date) })
        sickDates.insert(day)
        let number = OvertimeCalculator.sickStreakDayNumber(for: day, sickDates: sickDates, calendar: calendar)
        return (number, OvertimeCalculator.sickPayPercentage(streakDayNumber: number))
    }

    /// A sick day has no worked hours — `clockIn == clockOut` so `effectiveHours`
    /// is naturally 0, but `clockOut` is non-nil so it's never mistaken for an
    /// open/active session. Pay is computed separately in `OvertimeCalculator`
    /// from the sick-day streak, not from these times.
    ///
    /// Returns `false` (and surfaces `L10n.sickDayCapReached`) when adding the
    /// day would push the worker past the annual sick-day allowance — sick days
    /// accrue at 1.5 days/month in practice, so 18 per calendar year is the cap.
    @discardableResult
    func addSickDay(date: Date, notes: String?) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let alreadySickThatDay = sessions.contains {
            $0.dayType == .sick && calendar.isDate($0.date, inSameDayAs: day)
        }
        guard alreadySickThatDay || sickDaysUsed(inYearOf: day, calendar: calendar) < Self.sickDaysPerYearCap else {
            errorMessage = L10n.sickDayCapReached
            return false
        }
        let session = WorkSession(
            date: day,
            clockIn: day,
            clockOut: day,
            isManualEntry: true,
            dayType: .sick,
            notes: notes
        )
        sessions.append(session)
        persist()
        refreshReminders()
        syncWidget()
        ActivityLogStore.shared.log(
            L10n.logEventManualEntry,
            level: .success,
            category: "session",
            details: day.formatted(date: .abbreviated, time: .omitted)
        )
        return true
    }

    /// Annual sick-day allowance: sick days accrue at ~1.5 days/month in
    /// practice, i.e. 18 per calendar year.
    static let sickDaysPerYearCap = 18

    /// Number of sick days recorded in the calendar year of `date`.
    func sickDaysUsed(inYearOf date: Date, calendar: Calendar = .current) -> Int {
        let year = calendar.dateComponents([.year], from: date).year
        return sessions.filter {
            $0.dayType == .sick && calendar.dateComponents([.year], from: $0.date).year == year
        }.count
    }

    /// Applies a widget button tap (Clock In/Out) recorded in the shared
    /// App Group suite. Safe to call on every launch and every Darwin wake:
    /// a nil pending action is a no-op.
    func consumeWidgetActionIfNeeded() {
        // A widget tap can arrive while the phone is locked, when Data Protection
        // keeps our files unreadable. Retry the load; if the data is still locked,
        // leave the tap pending (it keeps its tap time) instead of applying it to
        // an empty in-memory state that `persist()` would refuse to save anyway.
        retryLoadIfNeeded()
        guard !sessionsLoadUnavailable, !settingsLoadUnavailable else { return }
        guard let pending = WidgetBridge.consumePendingActionWithDate() else { return }
        // Honor the tap time when the app only got to it later (it wasn't running),
        // but not for a stale tap from long ago — that's safer applied as "now".
        let tappedAt = pending.tappedAt.flatMap { date in
            Date().timeIntervalSince(date) < 12 * 3600 ? date : nil
        } ?? Date()
        switch pending.action {
        case .clockIn: clockIn(at: tappedAt)
        case .clockOut: clockOut()
        case .startBreak: startBreak(at: tappedAt)
        case .endBreak: endBreak(at: tappedAt)
        }
    }

    /// Keeps the long-press app-icon shortcuts in sync with the clock state.
    func refreshAppShortcuts() {
        AppShortcutManager.refresh(isClockedIn: sessions.contains(where: \.isOpen))
    }

    // MARK: - Manual Entry

    func addManualSession(
        date: Date,
        clockIn: Date,
        clockOut: Date,
        notes: String?,
        breakMinutes: Int = 0,
        dayType: DayType? = nil,
        isNightShift: Bool? = nil
    ) {
        // Multiple completed shifts on the same day are allowed (same as clock-in).
        let day = Calendar.current.startOfDay(for: date)

        let resolved = WorkSession.resolveClockPair(clockIn: clockIn, clockOut: clockOut)
        let session = WorkSession(
            date: day,
            clockIn: resolved.clockIn,
            clockOut: resolved.clockOut,
            isManualEntry: true,
            breakMinutes: breakMinutes,
            dayType: dayType ?? resolvedDayType(for: day),
            isNightShift: isNightShift
                ?? WorkSession.qualifiesAsNightShift(clockIn: resolved.clockIn, clockOut: resolved.clockOut),
            notes: notes
        )
        sessions.append(session)
        persist()
        refreshReminders()
        syncWidget()
        ActivityLogStore.shared.log(
            L10n.logEventManualEntry,
            level: .success,
            category: "session",
            details: day.formatted(date: .abbreviated, time: .omitted)
        )
    }

    @discardableResult
    func importScannedSessions(
        _ drafts: [ScannedSessionDraft],
        overwriteDays: Set<Date> = [],
        markAsAIImported: Bool = true
    ) -> Int {
        guard !drafts.isEmpty else { return 0 }
        let calendar = Calendar.current
        let overwriteKeys = Set(overwriteDays.map { calendar.startOfDay(for: $0).timeIntervalSince1970 })
        var importedCount = 0

        for draft in drafts where draft.isSelected {
            let resolved = WorkSession.resolveClockPair(clockIn: draft.clockIn, clockOut: draft.clockOut)
            guard resolved.clockOut > resolved.clockIn else { continue }
            let day = calendar.startOfDay(for: draft.date)
            let key = day.timeIntervalSince1970
            let existing = sessions.filter { calendar.isDate($0.date, inSameDayAs: day) }

            // An active ongoing shift must NEVER be silently overwritten or
            // deleted — not even when the user confirmed an overwrite for that
            // day. Days with an open shift are rejected here so the only path
            // past them is the explicit ImportConflictPopup flow (which lists
            // them via `conflictingDays`). This also prevents an imported row
            // from overlapping the running shift's time interval.
            if existing.contains(where: \.isOpen) {
                continue
            }
            if !existing.isEmpty {
                guard overwriteKeys.contains(key) else { continue }
                sessions.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
            }

            var session = draft.toWorkSession(isAIImported: markAsAIImported)
            session.date = day
            session.clockIn = resolved.clockIn
            session.clockOut = resolved.clockOut
            session.dayType = resolvedDayType(for: day)
            session.isNightShift = WorkSession.qualifiesAsNightShift(
                clockIn: resolved.clockIn,
                clockOut: resolved.clockOut
            )
            sessions.append(session)
            importedCount += 1
        }

        guard importedCount > 0 else { return 0 }

        persist()
        refreshReminders()
        syncWidget()
        ActivityLogStore.shared.log(
            L10n.logEventImport(importedCount),
            level: .success,
            category: "import",
            details: overwriteDays.isEmpty ? nil : L10n.logEventImportOverwrite(overwriteDays.count)
        )
        return importedCount
    }

    func existingCompletedSession(on day: Date) -> WorkSession? {
        let calendar = Calendar.current
        return sessions.first {
            calendar.isDate($0.date, inSameDayAs: day) && $0.clockOut != nil
        }
    }

    func conflictingDays(for drafts: [ScannedSessionDraft]) -> [Date] {
        let calendar = Calendar.current
        var days: [Date] = []
        var seen = Set<TimeInterval>()
        for draft in drafts where draft.isSelected {
            let day = calendar.startOfDay(for: draft.date)
            let key = day.timeIntervalSince1970
            guard seen.insert(key).inserted else { continue }
            if existingCompletedSession(on: day) != nil || sessions.contains(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                days.append(day)
            }
        }
        return days.sorted()
    }

    func updateSession(
        _ session: WorkSession,
        clockIn: Date,
        clockOut: Date?,
        notes: String?,
        breakMinutes: Int? = nil,
        dayType: DayType? = nil,
        isNightShift: Bool? = nil
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        if let clockOut {
            // The shift editor uses explicit date+time pickers, so the values
            // are authoritative — no swapped-times heuristic here. That
            // correction (`resolveClockPair`) only applies to OCR imports and
            // the same-day wheel pickers of manual entry, where reversed
            // times are genuinely ambiguous.
            sessions[index].clockIn = clockIn
            sessions[index].clockOut = clockOut
            sessions[index].date = Calendar.current.startOfDay(for: clockIn)
            sessions[index].isNightShift = isNightShift
                ?? WorkSession.qualifiesAsNightShift(clockIn: clockIn, clockOut: clockOut)
        } else {
            sessions[index].clockIn = clockIn
            sessions[index].clockOut = nil
            sessions[index].date = Calendar.current.startOfDay(for: clockIn)
            if let isNightShift {
                sessions[index].isNightShift = isNightShift
            }
        }
        sessions[index].notes = notes
        if let breakMinutes {
            sessions[index].breakMinutes = max(0, breakMinutes)
        }
        if let dayType {
            sessions[index].dayType = dayType
        }
        sessions[index].touch()
        persist()
        refreshReminders()
        syncWidget()
        ActivityLogStore.shared.log(
            L10n.logEventSessionUpdated,
            level: .info,
            category: "session"
        )
    }

    func deleteSession(_ session: WorkSession) {
        // Into "Recently deleted" (30 days) rather than gone — and offer an Undo.
        try? deletedSessions.add(session)
        sessions.removeAll { $0.id == session.id }
        offerUndo(for: session)
        persist()
        refreshReminders()
        syncWidget()
        ActivityLogStore.shared.log(
            L10n.logEventSessionDeleted,
            level: .warning,
            category: "session"
        )
    }

    /// Deletes several shifts at once (History multi-select). Same safety as a
    /// single delete: each goes into "Recently deleted" for 30 days, and one
    /// Undo banner puts them all back.
    func deleteSessions(_ toDelete: [WorkSession]) {
        guard !toDelete.isEmpty else { return }
        if toDelete.count == 1 {
            deleteSession(toDelete[0])
            return
        }
        for session in toDelete {
            try? deletedSessions.add(session)
        }
        let ids = Set(toDelete.map(\.id))
        sessions.removeAll { ids.contains($0.id) }
        offerUndo(for: toDelete[0])
        undoableBulkIDs = toDelete.map(\.id)
        persist()
        refreshReminders()
        syncWidget()
        ActivityLogStore.shared.log(
            L10n.logEventSessionDeleted + " ×\(toDelete.count)",
            level: .warning,
            category: "session"
        )
    }

    /// How many shifts the Undo banner would bring back (1 for a single delete).
    var undoableDeletionCount: Int {
        undoableDeletion == nil ? 0 : max(1, undoableBulkIDs.count)
    }

    // MARK: - Recently deleted / undo

    /// Shifts deleted in the last 30 days, newest first.
    var recentlyDeletedSessions: [DeletedSession] {
        deletedSessions.load()
    }

    /// Undo the delete whose banner is showing.
    func undoLastDeletion() {
        guard let session = undoableDeletion else { return }
        let bulk = undoableBulkIDs
        guard bulk.count > 1 else {
            restoreDeletedSession(id: session.id)
            return
        }
        clearUndo()
        var restoredIDs: [UUID] = []
        for id in bulk {
            guard let entry = try? deletedSessions.remove(id: id),
                  !sessions.contains(where: { $0.id == id }) else { continue }
            var restored = entry.session
            restored.touch()
            sessions.append(restored)
            restoredIDs.append(id)
        }
        guard !restoredIDs.isEmpty else { return }
        store.forgetDeletions(ids: Set(restoredIDs))
        sessions.sort { $0.clockIn < $1.clockIn }
        persist()
        syncWidget()
        ActivityLogStore.shared.log(L10n.logEventSessionRestored, level: .success, category: "session")
    }

    /// Puts a deleted shift back (from Undo or the Recently Deleted list).
    func restoreDeletedSession(id: UUID) {
        guard let entry = try? deletedSessions.remove(id: id) else { return }
        clearUndo()
        guard !sessions.contains(where: { $0.id == id }) else { return }
        var restored = entry.session
        restored.touch()
        store.forgetDeletions(ids: [id])
        sessions.append(restored)
        sessions.sort { $0.clockIn < $1.clockIn }
        persist()
        syncWidget()
        ActivityLogStore.shared.log(L10n.logEventSessionRestored, level: .success, category: "session")
    }

    /// Removes a shift from Recently Deleted for good.
    func deleteForever(id: UUID) {
        _ = try? deletedSessions.remove(id: id)
        objectWillChange.send()
    }

    private func offerUndo(for session: WorkSession) {
        undoableBulkIDs = []
        undoableDeletion = session
        undoClearTask?.cancel()
        undoClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.undoableDeletion = nil
            self?.undoableBulkIDs = []
        }
    }

    private func clearUndo() {
        undoClearTask?.cancel()
        undoableDeletion = nil
        undoableBulkIDs = []
    }

    // MARK: - Automatic backups

    /// Automatic on-device backups, newest first.
    var localBackups: [LocalBackup] {
        backups.list()
    }

    /// Re-attempts a load that came back `.temporarilyUnavailable` — e.g. the
    /// process was woken by a widget / Live Activity tap while Data Protection still
    /// had the files locked, so the first `load()` in `init()` lost the race.
    /// Without this the flags stay set for the process's life: an empty History and
    /// every `persist()` refused (by design, so the intact file is never
    /// overwritten) until a force-quit. Called whenever the app becomes active.
    /// A no-op when the last load was fine, so in-memory state is never clobbered.
    func retryLoadIfNeeded() {
        guard sessionsLoadUnavailable || settingsLoadUnavailable else { return }
        load()
    }

    /// Today's automatic backup (once a day). Taken at launch and whenever the app
    /// comes to the foreground — i.e. before the day's changes — with the first save
    /// of the day as a fallback. Skipped while the data couldn't be read, so an
    /// empty stand-in is never backed up.
    func takeDailyBackupIfNeeded() {
        guard !sessionsLoadUnavailable, !settingsLoadUnavailable else { return }
        backups.backupIfNeeded(settings: settings, sessions: sessions)
    }

    /// Replaces the current shifts and settings with a backup's. The current state is
    /// backed up first, so restoring the wrong day can be undone too. The activity
    /// log is left alone (backups don't carry it).
    func restoreBackup(_ backup: LocalBackup) throws {
        let document = try backups.load(backup.url)
        backups.backupBeforeRestore(settings: settings, sessions: sessions)
        sessionsLoadUnavailable = false
        settingsLoadUnavailable = false
        store.forgetDeletions(ids: Set(document.sessions.map(\.id)))
        sessions = document.sessions.sorted { $0.clockIn < $1.clockIn }
        settings = document.settings
        do {
            try store.saveSessions(sessions)
            try store.saveSettings(settings)
        } catch {
            errorMessage = L10n.errorSaveFailed
            throw error
        }
        refreshReminders()
        syncWidget()
        ActivityLogStore.shared.log(
            L10n.logEventBackupRestored,
            level: .success,
            category: "backup",
            details: "\(document.sessions.count)"
        )
    }

    // MARK: - Automatic account backup

    /// Keeps the signed-in account's cloud copy current: uploads a few seconds after
    /// the last change. It only ever *adds to* what's in the account — if the cloud
    /// copy has a shift this device doesn't (another device, or a reinstall that
    /// hasn't restored yet), the automatic upload stands down instead of overwriting
    /// it; the manual "Sync now" in Account still works as before.
    private func scheduleAccountBackup() {
        guard SupabaseAuthManager.shared.isSignedIn else { return }
        accountBackupTask?.cancel()
        accountBackupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            let local = self.sessions
            guard !local.isEmpty else { return }
            let localIDs = Set(local.map(\.id))
            let deletedIDs = Set(self.deletedSessions.load().map(\.id))
            let sync = SupabaseAccountSyncManager.shared
            do {
                if let remote = try await sync.downloadBackup() {
                    let missingLocally = Set(remote.sessions.map(\.id))
                        .subtracting(localIDs)
                        .subtracting(deletedIDs)
                    guard missingLocally.isEmpty else {
                        ActivityLogStore.shared.log(
                            L10n.logEventAutoBackupSkipped,
                            level: .warning,
                            category: "backup",
                            details: "\(missingLocally.count)"
                        )
                        return
                    }
                }
                // Keep the account's family name — passing nil would clear it.
                let profile = await sync.fetchProfile()
                try await sync.uploadBackup(
                    settings: self.settings,
                    sessions: local,
                    fullName: self.settings.workerFullName,
                    familyName: profile?.familyName
                )
            } catch {
                // Offline or server error: the next change retries.
            }
        }
    }

    // MARK: - Settings

    func saveSettings(_ newSettings: WorkplaceSettings) {
        var updated = newSettings
        updated.modifiedAt = Date()
        let remindersJustEnabled = updated.arrivalRemindersEnabled && !settings.arrivalRemindersEnabled
        let remindersJustDisabled = !updated.arrivalRemindersEnabled && settings.arrivalRemindersEnabled
        settings = updated
        persistSettings()
        // Session snapshots depend on settings too (e.g. whether breaks are paid), so
        // refresh widgets / Live Activity / Watch, not just the settings snapshot.
        syncWidget()
        if remindersJustEnabled {
            locationManager.requestArrivalReminderPermissions()
            refreshLocationPermissionStatuses()
            ActivityLogStore.shared.log(
                L10n.logEventRemindersOn,
                level: .info,
                category: "location"
            )
        }
        if remindersJustDisabled {
            locationManager.stopArrivalReminders()
            ActivityLogStore.shared.log(
                L10n.logEventRemindersOff,
                level: .info,
                category: "location"
            )
        }
        refreshReminders()
        ActivityLogStore.shared.log(
            L10n.logEventSettingsSaved,
            level: .info,
            category: "settings"
        )
    }

    /// Erases all local data and, when CloudKit is supported, remote copies too
    /// (Guideline 5.1.1 data control). National ID Keychain item is cleared via settings reset.
    func deleteAllUserData() {
        let cloudSessionIDs = Set(sessions.map(\.id))
        sessions = []
        settings = .default
        do {
            try store.saveSessions(sessions)
            // Avoid re-uploading default settings; cloud purge removes the record instead.
            try store.saveSettingsLocally(settings)
        } catch {
            errorMessage = L10n.errorSaveFailed
        }
        locationManager.stopArrivalReminders()
        refreshReminders()
        ExportTempFileStore.wipeAll()
        PayslipStore.wipeAll()
        // "Delete all my data" means the safety copies too.
        deletedSessions.removeAll()
        backups.removeAll()
        clearUndo()
        AnnouncementCenter.shared.forget()
        accountBackupTask?.cancel()
        PersistenceManager.shared.wipeQuarantinedSidecars()
        SessionTombstoneStore.shared.removeAll()
        SessionTombstoneStore.shared.wipeQuarantinedSidecars()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        ActivityLogStore.shared.wipeForPrivacy()
        ActivityLogStore.shared.log(
            L10n.logEventDataDeleted,
            level: .warning,
            category: "privacy"
        )

        guard store.isCloudSyncSupported else { return }
        Task {
            do {
                try await store.purgeCloudData(sessionIDs: cloudSessionIDs)
            } catch {
                errorMessage = L10n.privacyDeleteCloudPartialFailure
            }
        }
    }

    /// Import a JSON full-data export previously created via Settings → Export all my data.
    func importFullDataExport(_ document: FullDataExportDocument, mode: FullDataImportMode) throws {
        sessionsLoadUnavailable = false
        settingsLoadUnavailable = false

        switch mode {
        case .replace:
            sessions = document.sessions.sorted { $0.clockIn < $1.clockIn }
            settings = document.settings
            ActivityLogStore.shared.replaceEntries(document.activityLog)
        case .merge:
            var byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
            for session in document.sessions {
                byID[session.id] = session
            }
            sessions = Array(byID.values).sorted { $0.clockIn < $1.clockIn }
            settings = document.settings
            ActivityLogStore.shared.mergeEntries(document.activityLog)
        }

        do {
            try store.saveSessions(sessions)
            try store.saveSettings(settings)
        } catch {
            errorMessage = L10n.errorSaveFailed
            throw error
        }

        refreshReminders()
        ActivityLogStore.shared.log(
            L10n.logEventFullDataImport,
            level: .success,
            category: "import",
            details: mode.rawValue
        )
        objectWillChange.send()
    }

    func captureCurrentLocation() {
        locationCapture.capture()
    }

    func applyCapturedLocationIfAvailable() {
        guard let location = locationCapture.lastLocation else { return }
        applyLocation(location)
    }

    private func applyLocation(_ location: CLLocation) {
        settings.locationLatitude = location.coordinate.latitude
        settings.locationLongitude = location.coordinate.longitude
        settings.modifiedAt = Date()
        persistSettings()
        locationManager.updateWorkplaceLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radius: settings.locationRadiusMeters
        )
        refreshReminders()
        ActivityLogStore.shared.log(
            L10n.logEventLocationSet,
            level: .success,
            category: "location"
        )
    }

    // MARK: - Sync

    func syncNow() {
        guard isICloudSyncEnabled else { return }
        guard !isSyncing else { return }
        syncState = .syncing
        Task {
            do {
                if let result = try await store.syncNow() {
                    sessions = result.sessions
                    settings = result.settings
                    // Server-authoritative refresh cleared the "temporarily
                    // unavailable" state — future persists are safe again.
                    sessionsLoadUnavailable = false
                    settingsLoadUnavailable = false
                    refreshReminders()
                    // Server-authoritative sessions/settings just replaced the in-memory
                    // state, so the widget's App Group snapshot needs pushing too — it
                    // otherwise only refreshes on a local clock in/out.
                    syncWidget()
                }
                syncState = store.syncState
            } catch {
                syncState = store.syncState
            }
        }
    }

    /// Turns iCloud sync off and optionally erases already-uploaded private-DB copies.
    func disableICloudSync(deleteRemoteData: Bool) {
        isICloudSyncEnabled = false
        guard deleteRemoteData, isCloudSyncSupported else { return }
        let ids = Set(sessions.map(\.id))
        Task {
            do {
                try await store.purgeCloudData(sessionIDs: ids)
            } catch {
                errorMessage = L10n.privacyDeleteCloudPartialFailure
            }
        }
    }

    // MARK: - History

    var sortedSessions: [WorkSession] {
        sessions
            .filter { $0.clockOut != nil }
            .sorted { $0.date > $1.date }
    }

    /// Day-aware: same-day sessions share one daily overtime/gas allowance.
    func breakdown(for session: WorkSession) -> DayPayBreakdown {
        OvertimeCalculator.breakdown(for: session, in: sessions, settings: settings)
    }

    // MARK: - Export

    func export(
        range: ExportDateRange,
        format: ExportFormat,
        language: ExportLanguage = .phone,
        dayTypes: Set<DayType>? = nil,
        includeNotes: Bool = false
    ) throws -> URL {
        let report = exportManager.buildReport(
            sessions: sessions,
            settings: settings,
            range: range,
            language: language,
            dayTypes: dayTypes,
            includeNotes: includeNotes
        )
        let url = try exportManager.export(report: report, format: format, language: language)
        ActivityLogStore.shared.log(
            L10n.logEventExport,
            level: .success,
            category: "export",
            details: "\(format.fileExtension) / \(String(describing: language))"
        )
        return url
    }

    // MARK: - Private

    private func load() {
        switch store.loadSessionsResult() {
        case .loaded(let loaded):
            sessions = loaded
            sessionsLoadUnavailable = false
        case .missing, .corruptQuarantined:
            sessions = []
            sessionsLoadUnavailable = false
        case .temporarilyUnavailable:
            // Keep the (default empty) in-memory `sessions` value, but flag it
            // so `persist()` will NOT overwrite the intact-but-unreadable file.
            sessionsLoadUnavailable = true
            errorMessage = L10n.errorSaveFailed
        }

        switch store.loadSettingsResult() {
        case .loaded(let loaded):
            settings = loaded
            settingsLoadUnavailable = false
        case .missing, .corruptQuarantined:
            settings = .default
            settingsLoadUnavailable = false
        case .temporarilyUnavailable:
            settingsLoadUnavailable = true
            errorMessage = L10n.errorSaveFailed
        }
    }

    private func persist() {
        // Refuse to save when the on-disk file is intact but was unreadable at
        // load time. Otherwise we would overwrite it with the current (empty
        // or partial) in-memory `sessions` and silently wipe the user's data.
        if sessionsLoadUnavailable {
            errorMessage = L10n.errorSaveFailed
            refreshReminders()
            return
        }
        do {
            try store.saveSessions(sessions)
            takeDailyBackupIfNeeded()
            scheduleAccountBackup()
        } catch {
            errorMessage = L10n.errorSaveFailed
        }
        refreshReminders()
    }

    private func persistSettings() {
        if settingsLoadUnavailable {
            errorMessage = L10n.errorSaveFailed
            return
        }
        do {
            try store.saveSettings(settings)
        } catch {
            errorMessage = L10n.errorSaveFailed
        }
        WidgetBridge.update(settings: WidgetBridge.snapshot(from: settings))
        WidgetBridge.reloadWidgetTimelines()
        refreshAppShortcuts()
        WatchConnectivityManager.shared.pushSnapshot()
    }

    private func refreshReminders() {
        locationManager.configure(settings: settings, sessions: sessions)
        ShiftReminderScheduler.reschedule(sessions: sessions, settings: settings)
    }

    /// Rebuilds the "clock in / clock out" reminders — after a Notifications toggle
    /// changes, and when the app comes to the foreground (the plan only reaches a
    /// week ahead, so it's topped up whenever the app is used).
    func refreshShiftReminders() {
        ShiftReminderScheduler.reschedule(sessions: sessions, settings: settings)
    }

    /// Push current sessions and settings to the WidgetKit extension
    /// and update the Live Activity (if one is running).
    private func syncWidget() {
        let curve = refreshLiveCurve()
        let showsNet = livePayShowsNet
        WidgetBridge.pushUpdate(settings: settings, sessions: sessions, livePay: curve, livePayShowsNet: showsNet)
        WatchConnectivityManager.shared.pushSnapshot()
        if #available(iOS 16.1, *) {
            if let open = activeSession {
                LiveActivityManager.update(session: open, settings: settings, curve: curve, showsNet: showsNet)
            } else if !sessionsLoadUnavailable {
                // No open shift (clocked out, closed in the editor, deleted, or closed
                // on another device): no banner may stay on the Lock Screen. Skipped
                // while the shifts couldn't be read, so a locked store at a
                // background launch never ends a real shift's banner.
                LiveActivityManager.endAll()
            }
        }
    }

    /// Re-pushes the live figures to the widgets, Watch and Live Activity — e.g. after
    /// Home's gross/net picker changes which figure they should show.
    ///
    /// Debounced (`liveSurfacesDebounce`): quick repeated taps send one update with the
    /// final choice instead of a burst of Live Activity / widget reloads.
    func refreshLiveSurfaces() {
        liveSurfacesTask?.cancel()
        liveSurfacesTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.liveSurfacesDebounce)
            guard !Task.isCancelled, let self else { return }
            self.liveSurfacesPushCount += 1
            self.lastLiveSurfacesShowsNet = self.livePayShowsNet
            self.syncWidget()
        }
    }

    static let liveSurfacesDebounce: Duration = .milliseconds(300)

    /// Rebuilds `liveCurve` when the open shift, the settings or the session list
    /// changed since it was built (building it prices ~200 samples), and clears it
    /// when nothing is open.
    @discardableResult
    func refreshLiveCurve() -> LivePayCurve? {
        guard let open = activeSession else {
            liveCurve = nil
            liveCurveInputs = nil
            return nil
        }
        let inputs = LiveCurveInputs(session: open, settings: settings, sessionCount: sessions.count)
        if inputs != liveCurveInputs || liveCurve == nil {
            liveCurve = makeLivePayCurve(for: open)
            liveCurveInputs = inputs
        }
        return liveCurve
    }

    /// Live Activity content (elapsed hours/time, estimated pay) is a static
    /// snapshot pushed once via `syncWidget()` at clock-in — `LiveActivityManager`
    /// never updates it again on its own (its displayed timer is plain `Text`,
    /// not a self-updating `.timer`-style one), so without a periodic push the
    /// Lock Screen banner freezes at ~0 for the rest of the shift. This loop is
    /// the "app's timer" `LiveActivityManager.update`'s doc comment expects.
    /// Runs only while a session is open; otherwise it just idles.
    private func startLiveActivityRefreshLoop() {
        liveActivityRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                if self.activeSession != nil {
                    self.syncWidget()
                }
            }
        }
    }
}
