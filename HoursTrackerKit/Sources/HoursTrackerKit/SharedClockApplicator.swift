import Foundation

/// Shared clock-in / clock-out mutation used by Watch, widgets, and phone reconcile.
/// Idempotent: duplicate session IDs and double clock-in/out are no-ops.
public enum SharedClockApplicator {
    public static func apply(
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

    /// Apply a list of pending events in order (phone / watch merge path).
    public static func merge(
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
}
