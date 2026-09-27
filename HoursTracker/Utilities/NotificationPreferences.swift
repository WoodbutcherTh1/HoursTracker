import Foundation

/// Per-feature on/off switches for every notification the app can send, so the
/// user decides which features may notify them (Settings → Notifications).
///
/// Location reminders are not here: they already live in `WorkplaceSettings`
/// (`arrivalRemindersEnabled`) because they also drive the geofence itself; the
/// Notifications screen binds to that setting directly.
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()

    /// Lead times offered for the "break ending soon" reminder.
    static let breakLeadTimeOptions = [2, 5, 10]
    /// Break lengths offered in Settings.
    static let breakTargetOptions = [15, 20, 30, 45, 60]

    private enum Key {
        static let breakEndingSoon = "notifications.breakEndingSoon"
        static let breakLeadMinutes = "notifications.breakLeadMinutes"
        static let breakOver = "notifications.breakOver"
        static let breakTargetMinutes = "breaks.targetMinutes"
        static let shiftStart = "notifications.shiftStart"
        static let shiftEnd = "notifications.shiftEnd"
        static let announcements = "notifications.announcements"
    }

    private let defaults: UserDefaults

    /// "Your break ends in N minutes."
    @Published var breakEndingSoonEnabled: Bool {
        didSet { defaults.set(breakEndingSoonEnabled, forKey: Key.breakEndingSoon) }
    }

    /// How many minutes before the break ends the heads-up fires.
    @Published var breakLeadMinutes: Int {
        didSet { defaults.set(breakLeadMinutes, forKey: Key.breakLeadMinutes) }
    }

    /// "Your break is over — back to work."
    @Published var breakOverEnabled: Bool {
        didSet { defaults.set(breakOverEnabled, forKey: Key.breakOver) }
    }

    /// Planned break length the countdown runs against.
    @Published var breakTargetMinutes: Int {
        didSet { defaults.set(breakTargetMinutes, forKey: Key.breakTargetMinutes) }
    }

    /// Reminder shortly before the usual shift start (clock in).
    @Published var shiftStartReminderEnabled: Bool {
        didSet { defaults.set(shiftStartReminderEnabled, forKey: Key.shiftStart) }
    }

    /// Reminder shortly before the usual shift end (clock out).
    @Published var shiftEndReminderEnabled: Bool {
        didSet { defaults.set(shiftEndReminderEnabled, forKey: Key.shiftEnd) }
    }

    /// Announcements from the app owner.
    @Published var announcementsEnabled: Bool {
        didSet { defaults.set(announcementsEnabled, forKey: Key.announcements) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        breakEndingSoonEnabled = defaults.object(forKey: Key.breakEndingSoon) as? Bool ?? true
        breakLeadMinutes = Self.clampLead(defaults.object(forKey: Key.breakLeadMinutes) as? Int ?? 5)
        breakOverEnabled = defaults.object(forKey: Key.breakOver) as? Bool ?? true
        breakTargetMinutes = Self.clampTarget(defaults.object(forKey: Key.breakTargetMinutes) as? Int ?? 30)
        shiftStartReminderEnabled = defaults.object(forKey: Key.shiftStart) as? Bool ?? true
        shiftEndReminderEnabled = defaults.object(forKey: Key.shiftEnd) as? Bool ?? true
        announcementsEnabled = defaults.object(forKey: Key.announcements) as? Bool ?? true
    }

    private static func clampLead(_ value: Int) -> Int {
        breakLeadTimeOptions.contains(value) ? value : 5
    }

    private static func clampTarget(_ value: Int) -> Int {
        (5...240).contains(value) ? value : 30
    }
}
