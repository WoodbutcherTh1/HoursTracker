import Foundation
import UserNotifications

/// Whether the Settings screen has edits that still need Save, plus what Save and
/// Discard do — so the tab bar can ask before leaving Settings, and a reminder can
/// go out when the app is left in the background with changes pending.
///
/// Only the fields behind Save count (worker, workplace, pay, rules, tax, location
/// reminders, Smart Scanner keys). Toggles that apply at once (language, app lock,
/// notification switches) never make Settings "unsaved".
@MainActor
final class SettingsUnsavedChanges: ObservableObject {
    static let shared = SettingsUnsavedChanges()

    @Published private(set) var hasChanges = false
    private var onSave: (() -> Void)?
    private var onDiscard: (() -> Void)?

    func update(hasChanges: Bool, save: @escaping () -> Void, discard: @escaping () -> Void) {
        self.hasChanges = hasChanges
        onSave = save
        onDiscard = discard
    }

    func save() { onSave?() }
    func discard() { onDiscard?() }
}

/// "You have unsaved changes in Settings" — scheduled when the app goes to the
/// background with changes pending, cancelled when it comes back first. Tapping it
/// opens Settings (changes still there); its Discard button drops them.
enum SettingsUnsavedReminder {
    static let identifier = "settings-unsaved"
    static let categoryID = "settings-unsaved"
    static let discardActionID = "settings-unsaved.discard"
    static let delay: TimeInterval = 60

    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryID,
            actions: [
                UNNotificationAction(identifier: discardActionID, title: L10n.settingsUnsavedDiscard, options: [.destructive])
            ],
            intentIdentifiers: []
        )
    }

    /// Only when notifications are already allowed — never asks for permission.
    static func schedule(center: UNUserNotificationCenter = .current()) {
        let content = UNMutableNotificationContent()
        content.title = LocationReminderManager.notificationTitle()
        content.body = L10n.settingsUnsavedNotification
        content.sound = .default
        content.categoryIdentifier = categoryID
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request)
            default:
                break
            }
        }
    }

    static func cancel(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
