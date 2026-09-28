import Foundation
import UserNotifications

/// "Your shift starts in 5 minutes — clock in?" / "…ends in 5 minutes — clock out?",
/// timed by the worker's usual schedule (`ShiftSchedule`), no location needed.
///
/// Start reminders are one-shot notifications for the next few days, rebuilt every
/// time the sessions change, so a day the worker already clocked in on never gets
/// one. The end reminder exists only while a shift is actually open. Both carry a
/// Clock In / Clock Out button that works straight from the notification.
enum ShiftReminderScheduler {
    enum Kind: Equatable {
        case start
        case end
    }

    struct Planned: Equatable {
        let id: String
        let kind: Kind
        let fireDate: Date
    }

    static let leadMinutes = 5
    static let horizonDays = 7
    static let idPrefix = "shift-reminder-"
    static let endID = "shift-reminder-end"

    static let startCategory = "shift.start"
    static let endCategory = "shift.end"
    static let clockInAction = "shift.clockIn"
    static let clockOutAction = "shift.clockOut"

    /// What to schedule. Pure, for tests.
    static func plan(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        schedule: ShiftSchedule,
        now: Date = Date(),
        startEnabled: Bool,
        endEnabled: Bool,
        calendar: Calendar = .current
    ) -> [Planned] {
        var planned: [Planned] = []
        let lead = TimeInterval(leadMinutes * 60)
        let open = sessions.filter(\.isOpen).max { $0.clockIn < $1.clockIn }

        if startEnabled {
            let today = calendar.startOfDay(for: now)
            for offset in 0..<horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let weekday = calendar.component(.weekday, from: day)
                guard !settings.isRestDayWeekday(weekday),
                      IsraeliHolidayCalendar.holiday(on: day, calendar: calendar) == nil,
                      let start = schedule.start(on: day, calendar: calendar) else { continue }
                // Already clocked in that day (or still in a shift today) — nothing to remind.
                if offset == 0, open != nil { continue }
                if sessions.contains(where: { calendar.isDate($0.clockIn, inSameDayAs: day) }) { continue }
                let fire = start.addingTimeInterval(-lead)
                guard fire > now else { continue }
                planned.append(Planned(id: idPrefix + "start-" + dayKey(day, calendar: calendar), kind: .start, fireDate: fire))
            }
        }

        if endEnabled, let open {
            let shiftDay = calendar.startOfDay(for: open.clockIn)
            var end = schedule.end(on: shiftDay, calendar: calendar)
            // Started much later than usual: aim for the usual *length* instead of
            // the usual end time, so the reminder isn't minutes after clocking in.
            if let usualEnd = end, usualEnd < open.clockIn.addingTimeInterval(60 * 60),
               let window = schedule.window(for: shiftDay, calendar: calendar) {
                end = open.clockIn.addingTimeInterval(TimeInterval(window.durationMinutes * 60))
            }
            if let end {
                let fire = end.addingTimeInterval(-lead)
                if fire > now {
                    planned.append(Planned(id: endID, kind: .end, fireDate: fire))
                }
            }
        }
        return planned
    }

    /// Replaces every pending shift reminder with a fresh plan. `askPermission` is
    /// set from clock-in — the moment the value of a reminder is obvious — so the
    /// app never asks for notification access out of the blue at launch.
    static func reschedule(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        preferences: NotificationPreferences = .shared,
        askPermission: Bool = false,
        center: UNUserNotificationCenter = .current()
    ) {
        let schedule = ShiftSchedule.learn(from: sessions)
        let planned = plan(
            sessions: sessions,
            settings: settings,
            schedule: schedule,
            startEnabled: preferences.shiftStartReminderEnabled,
            endEnabled: preferences.shiftEndReminderEnabled
        )
        // Resolve copy now (main thread, current in-app language); callbacks below
        // run on a background queue.
        let title = LocationReminderManager.notificationTitle()
        let startBody = AppLocale.shiftStartsSoon(minutes: leadMinutes)
        let endBody = AppLocale.shiftEndsSoon(minutes: leadMinutes)

        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            guard !planned.isEmpty else { return }

            let add = {
                for item in planned {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.sound = .default
                    content.body = item.kind == .start ? startBody : endBody
                    content.categoryIdentifier = item.kind == .start ? startCategory : endCategory
                    let parts = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: item.fireDate
                    )
                    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                    center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
                }
            }
            center.getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    add()
                case .notDetermined where askPermission:
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        if granted { add() }
                    }
                default:
                    break
                }
            }
        }
    }

    /// Clock In / Clock Out buttons on the reminders. They run in the background —
    /// the app isn't opened — but require the phone to be unlocked, since the app's
    /// data is protected while it's locked.
    static func registerCategories(center: UNUserNotificationCenter = .current()) {
        let clockIn = UNNotificationAction(
            identifier: clockInAction,
            title: L10n.homeClockIn,
            options: [.authenticationRequired]
        )
        let clockOut = UNNotificationAction(
            identifier: clockOutAction,
            title: L10n.homeClockOut,
            options: [.authenticationRequired]
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: startCategory, actions: [clockIn], intentIdentifiers: []),
            UNNotificationCategory(identifier: endCategory, actions: [clockOut], intentIdentifiers: []),
            SettingsUnsavedReminder.category
        ])
    }

    private static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
