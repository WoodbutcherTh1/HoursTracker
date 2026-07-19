import Foundation
import HoursTrackerKit
import UIKit
import UserNotifications

/// Handles Quick Export notification actions (Share) and registers the category at launch.
final class AppNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationCenter()

    /// Set by the app so Share can present through `AppViewModel`.
    @MainActor var onShareExport: (() -> Void)?

    private override init() {
        super.init()
    }

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories()
    }

    func registerCategories() {
        let share = UNNotificationAction(
            identifier: WidgetQuickExportStore.shareActionID,
            title: "Share",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: WidgetQuickExportStore.notificationCategoryID,
            actions: [share],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // Show banner even in foreground so path A is visible after Export from the widget.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.content.categoryIdentifier == WidgetQuickExportStore.notificationCategoryID {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        let isShare = category == WidgetQuickExportStore.notificationCategoryID
            && (action == WidgetQuickExportStore.shareActionID
                || action == UNNotificationDefaultActionIdentifier)
        if isShare {
            Task { @MainActor in
                self.onShareExport?()
            }
        }
        completionHandler()
    }
}
