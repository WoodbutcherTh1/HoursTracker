import Foundation
import UserNotifications

/// Local notifications for a running break: a heads-up shortly before the
/// planned break length is reached, and "break is over" when it is.
///
/// Both are one-shot time-interval notifications scheduled at break start and
/// removed as soon as the worker taps "back to work" (or clocks out), so an early
/// return never produces a stale "your break is over".
enum BreakReminderScheduler {
    enum Kind: Equatable {
        case endingSoon
        case over
    }

    struct Planned: Equatable {
        let kind: Kind
        let fireDate: Date
    }

    static let endingSoonID = "break-ending-soon"
    static let overID = "break-over"

    /// What to schedule for a break that started at `breakStart`. Pure, for tests.
    /// Anything whose fire time has already passed is skipped.
    static func plan(
        breakStart: Date,
        now: Date = Date(),
        targetMinutes: Int,
        leadMinutes: Int,
        endingSoonEnabled: Bool,
        overEnabled: Bool
    ) -> [Planned] {
        guard targetMinutes > 0 else { return [] }
        let end = breakStart.addingTimeInterval(TimeInterval(targetMinutes * 60))
        var result: [Planned] = []
        // The heads-up only makes sense when the break is longer than the lead time.
        if endingSoonEnabled, leadMinutes > 0, leadMinutes < targetMinutes {
            let soon = end.addingTimeInterval(TimeInterval(-leadMinutes * 60))
            if soon > now { result.append(Planned(kind: .endingSoon, fireDate: soon)) }
        }
        if overEnabled, end > now {
            result.append(Planned(kind: .over, fireDate: end))
        }
        return result
    }

    static func schedule(
        breakStart: Date,
        preferences: NotificationPreferences = .shared,
        center: UNUserNotificationCenter = .current()
    ) {
        cancel(center: center)
        let planned = plan(
            breakStart: breakStart,
            targetMinutes: preferences.breakTargetMinutes,
            leadMinutes: preferences.breakLeadMinutes,
            endingSoonEnabled: preferences.breakEndingSoonEnabled,
            overEnabled: preferences.breakOverEnabled
        )
        guard !planned.isEmpty else { return }
        let lead = preferences.breakLeadMinutes
        // Resolve copy now (main thread, current in-app language) — the callbacks
        // below run on a background queue.
        let title = LocationReminderManager.notificationTitle()
        let soonBody = AppLocale.breakEndingSoon(minutes: lead)
        let overBody = AppLocale.breakOver()

        center.getNotificationSettings { settings in
            let add = {
                for item in planned {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.sound = .default
                    content.body = item.kind == .endingSoon ? soonBody : overBody
                    let interval = max(1, item.fireDate.timeIntervalSinceNow)
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                    let id = item.kind == .endingSoon ? endingSoonID : overID
                    center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                }
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                add()
            case .notDetermined:
                // First break ever: ask now, when the value of the reminder is obvious.
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { add() }
                }
            default:
                break
            }
        }
    }

    static func cancel(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: [endingSoonID, overID])
        center.removeDeliveredNotifications(withIdentifiers: [endingSoonID, overID])
    }
}
