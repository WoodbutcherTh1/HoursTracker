import Foundation
import HoursTrackerKit
import SwiftUI
import WatchKit

/// Watch-side MVVM: optimistic clock + merge with phone snapshots.
@MainActor
final class WatchAppViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkSession] = []
    @Published private(set) var paySettings: WatchPaySettings
    @Published private(set) var isPhoneReachable = false

    private let connectivity: WatchConnectivitySessionManager
    private let persistence: WatchPersistenceManager
    private var phoneSnapshot: WatchSnapshot?

    init(
        connectivity: WatchConnectivitySessionManager = .shared,
        persistence: WatchPersistenceManager = .shared
    ) {
        self.connectivity = connectivity
        self.persistence = persistence
        if WatchScreenshotDemoData.isEnabled {
            let demo = WatchScreenshotDemoData.makeSnapshot(
                language: WatchScreenshotDemoData.preferredLanguage
            )
            persistence.save(demo)
            self.paySettings = demo.paySettings
            self.phoneSnapshot = demo
            self.sessions = demo.sessions
            connectivity.applyCachedSnapshot(demo)
        } else if let cached = persistence.load() {
            self.paySettings = cached.paySettings
            self.phoneSnapshot = cached
            self.sessions = Self.merge(phone: cached.sessions, pending: connectivity.pendingQueue.pending, pay: cached.paySettings)
        } else {
            self.paySettings = WatchPaySettings(
                hourlyRate: 0,
                dailyGasAllowance: 0,
                standardDayHours: 8.6,
                ot125HoursCap: 2,
                nightStandardDayHours: 7,
                defaultBreakMinutes: 0,
                restDayWeekday: 7,
                secondRestDayWeekday: nil,
                currencyCode: "ILS",
                language: .system
            )
        }
        bindConnectivity()
    }

    var activeSession: WorkSession? {
        sessions.filter(\.isOpen).max { $0.clockIn < $1.clockIn }
    }

    var isClockedIn: Bool { activeSession != nil }

    var canClockIn: Bool { !isClockedIn }

    var locale: Locale {
        switch paySettings.language {
        case .system: return .autoupdatingCurrent
        case .english: return Locale(identifier: "en")
        case .hebrew: return Locale(identifier: "he")
        case .arabic: return Locale(identifier: "ar")
        }
    }

    var layoutDirection: LayoutDirection {
        switch paySettings.language {
        case .hebrew, .arabic: return .rightToLeft
        case .english: return .leftToRight
        case .system:
            return Locale.Language(identifier: Locale.autoupdatingCurrent.identifier)
                .characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
        }
    }

    /// Completed sessions today + open session hours (live).
    func todayHours(now: Date = Date()) -> Double {
        let cal = Calendar.current
        let today = sessions.filter { cal.isDate($0.date, inSameDayAs: now) }
        var hours = today.filter { !$0.isOpen }.reduce(0.0) { $0 + $1.totalHours }
        if let open = activeSession, cal.isDate(open.date, inSameDayAs: now) {
            hours += max(0, now.timeIntervalSince(open.clockIn) / 3600)
        }
        return hours
    }

    /// Rough gross for completed today + live open session estimate.
    func todayGross(now: Date = Date()) -> Double {
        let settings = paySettings.workplaceSettingsForGrossEstimate()
        let cal = Calendar.current
        var completed = sessions.filter {
            cal.isDate($0.date, inSameDayAs: now) && !$0.isOpen
        }
        if let open = activeSession {
            var live = open
            live.clockOut = now
            completed.append(live)
        }
        return OvertimeCalculator.aggregate(sessions: completed, settings: settings).totalPay
    }

    func recentCompletedShifts(limit: Int = 5) -> [WorkSession] {
        sessions
            .filter { !$0.isOpen }
            .sorted { $0.clockIn > $1.clockIn }
            .prefix(limit)
            .map { $0 }
    }

    func toggleClock() {
        if isClockedIn {
            clockOut()
        } else {
            clockIn()
        }
    }

    func clockIn() {
        guard canClockIn else { return }
        let event = WatchClockEvent.makeClockIn()
        connectivity.sendClockEvent(event)
        recomputeFromPending()
        WKInterfaceDevice.current().play(.success)
    }

    func clockOut() {
        guard let open = activeSession else { return }
        let event = WatchClockEvent.makeClockOut(sessionID: open.id)
        connectivity.sendClockEvent(event)
        recomputeFromPending()
        WKInterfaceDevice.current().play(.click)
    }

    private func bindConnectivity() {
        isPhoneReachable = connectivity.isPhoneReachable
        connectivity.onSnapshot = { [weak self] snap in
            self?.applyPhoneSnapshot(snap)
        }
        if let snap = connectivity.snapshot {
            applyPhoneSnapshot(snap)
        }
    }

    func refreshReachability() {
        isPhoneReachable = connectivity.isPhoneReachable
    }

    /// Re-seed demo data after launch (UITest args are always available by then).
    func ensureScreenshotDemoIfNeeded() {
        guard WatchScreenshotDemoData.isEnabled else { return }
        let demo = WatchScreenshotDemoData.makeSnapshot(
            language: WatchScreenshotDemoData.preferredLanguage
        )
        phoneSnapshot = demo
        paySettings = demo.paySettings
        sessions = demo.sessions
        persistence.save(demo)
        connectivity.applyCachedSnapshot(demo)
    }

    private func applyPhoneSnapshot(_ snap: WatchSnapshot) {
        phoneSnapshot = snap
        paySettings = snap.paySettings
        persistence.save(snap)
        recomputeFromPending()
    }

    private func recomputeFromPending() {
        let base = phoneSnapshot?.sessions ?? []
        sessions = Self.merge(
            phone: base,
            pending: connectivity.pendingQueue.pending,
            pay: paySettings
        )
        // Keep a local cache that includes optimistic state for relaunch.
        let cache = WatchSnapshot(sessions: sessions, paySettings: paySettings)
        persistence.save(cache)
    }

    static func merge(
        phone: [WorkSession],
        pending: [WatchClockEvent],
        pay: WatchPaySettings
    ) -> [WorkSession] {
        var sessions = phone
        let settings = pay.workplaceSettingsForGrossEstimate()
        for event in pending {
            apply(event, to: &sessions, settings: settings)
        }
        return sessions
    }

    static func apply(
        _ event: WatchClockEvent,
        to sessions: inout [WorkSession],
        settings: WorkplaceSettings
    ) {
        switch event.kind {
        case .clockIn:
            if sessions.contains(where: { $0.id == event.sessionID }) { return }
            if sessions.contains(where: \.isOpen) { return }
            sessions.append(
                WorkSession(
                    id: event.sessionID,
                    date: Calendar.current.startOfDay(for: event.timestamp),
                    clockIn: event.timestamp,
                    clockOut: nil,
                    isManualEntry: false,
                    dayType: DayType.automatic(for: event.timestamp, settings: settings)
                )
            )
        case .clockOut:
            guard let index = sessions.firstIndex(where: { $0.id == event.sessionID && $0.isOpen })
                    ?? sessions.firstIndex(where: { $0.isOpen })
            else { return }
            sessions[index].clockOut = event.timestamp
            sessions[index].isNightShift = WorkSession.qualifiesAsNightShift(
                clockIn: sessions[index].clockIn,
                clockOut: event.timestamp
            )
            sessions[index].touch()
        }
    }
}
