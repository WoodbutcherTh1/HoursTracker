import Foundation
import UserNotifications

/// A gentle, local reminder to add the Home Screen widget, for people who haven't.
///
/// - Two days after first use, at 19:00; one more reminder two weeks later. Never more.
/// - Written in the app's current language when it's scheduled.
/// - Cancelled as soon as a widget is placed; never asks for notification permission.
/// - Tapping it opens Settings → the widget install guide (iOS has no API to add a
///   widget for the user, so the guide is the shortest honest path).
enum WidgetNudge {
    static let firstID = "widget.nudge.1"
    static let secondID = "widget.nudge.2"
    static let userInfoKey = "widgetNudge"
    static let openGuide = Notification.Name("WidgetNudge.openGuide")
    static let deepLink = URL(string: "hourstracker://widgetGuide")!

    private static let firstUseKey = "widgetNudge.firstUse"
    private static let scheduledKey = "widgetNudge.scheduled"

    /// Set when the reminder was tapped before Settings was on screen.
    @MainActor static var pendingGuide = false

    /// Call when the app becomes active.
    static func refresh(defaults: UserDefaults = .standard) async {
        if defaults.object(forKey: firstUseKey) == nil {
            defaults.set(Date(), forKey: firstUseKey)
        }
        let center = UNUserNotificationCenter.current()

        if let count = await WidgetBridge.installedWidgetCount(), count > 0 {
            center.removePendingNotificationRequests(withIdentifiers: [firstID, secondID])
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let firstUse = defaults.object(forKey: firstUseKey) as? Date ?? Date()
        var scheduled = Set(defaults.stringArray(forKey: scheduledKey) ?? [])
        for (id, days) in [(firstID, 2), (secondID, 16)] where !scheduled.contains(id) {
            guard let fireDate = evening(daysAfter: days, from: firstUse), fireDate > Date() else {
                scheduled.insert(id)   // that moment has passed; don't send it late
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = L10n.widgetNudgeTitle
            content.body = L10n.widgetNudgeBody
            content.sound = .default
            content.userInfo = [userInfoKey: true]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            if (try? await center.add(request)) != nil {
                scheduled.insert(id)
            }
        }
        defaults.set(Array(scheduled), forKey: scheduledKey)
    }

    private static func evening(daysAfter days: Int, from start: Date) -> Date? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: start)) else { return nil }
        return calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day)
    }
}
