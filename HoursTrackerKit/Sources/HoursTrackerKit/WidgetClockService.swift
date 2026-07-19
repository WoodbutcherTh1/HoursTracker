import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Optimistic clock mutations for widgets (and any App Intent) against the App Group snapshot.
public enum WidgetClockService {
    public enum Outcome: Equatable, Sendable {
        case clockedIn
        case clockedOut
        case rejectedAlreadyIn
        case rejectedNoOpenSession
        case rejectedNoSnapshot
    }

    @discardableResult
    public static func clockIn(at date: Date = Date()) -> Outcome {
        guard var snapshot = WatchSharedStore.loadSnapshot() else {
            return .rejectedNoSnapshot
        }
        if snapshot.sessions.contains(where: \.isOpen) {
            return .rejectedAlreadyIn
        }
        let event = WatchClockEvent.makeClockIn(at: date)
        var sessions = snapshot.sessions
        SharedClockApplicator.apply(
            event,
            to: &sessions,
            settings: snapshot.paySettings.workplaceSettingsForGrossEstimate()
        )
        snapshot.sessions = sessions
        snapshot.updatedAt = Date()
        WatchSharedStore.saveSnapshot(snapshot)
        WidgetPendingEventStore.enqueue(event)
        reloadTimelines()
        return .clockedIn
    }

    @discardableResult
    public static func clockOut(at date: Date = Date()) -> Outcome {
        guard var snapshot = WatchSharedStore.loadSnapshot() else {
            return .rejectedNoSnapshot
        }
        guard let open = snapshot.sessions.filter(\.isOpen).max(by: { $0.clockIn < $1.clockIn }) else {
            return .rejectedNoOpenSession
        }
        let event = WatchClockEvent.makeClockOut(sessionID: open.id, at: date)
        var sessions = snapshot.sessions
        SharedClockApplicator.apply(
            event,
            to: &sessions,
            settings: snapshot.paySettings.workplaceSettingsForGrossEstimate()
        )
        snapshot.sessions = sessions
        snapshot.updatedAt = Date()
        WatchSharedStore.saveSnapshot(snapshot)
        WidgetPendingEventStore.enqueue(event)
        reloadTimelines()
        return .clockedOut
    }

    @discardableResult
    public static func toggle(at date: Date = Date()) -> Outcome {
        guard let snapshot = WatchSharedStore.loadSnapshot() else {
            return .rejectedNoSnapshot
        }
        if snapshot.sessions.contains(where: \.isOpen) {
            return clockOut(at: date)
        }
        return clockIn(at: date)
    }

    private static func reloadTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
