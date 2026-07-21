import AppIntents
import Foundation

#if os(iOS)
import UserNotifications
import WidgetKit

/// Follow-up after `QuickExportIntent`.
/// Opens the iPhone Export tab only when `WidgetQuickExportStore` has the ready flag
/// (path B). Path A leaves the flag clear so Siri/widget stay in-place for the notification.
public struct OpenExportReadyIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open Export"
    public static var description = IntentDescription("Open HoursTracker on the Export screen.")

    /// Evaluated when the follow-up runs — true only if Quick Export marked the flag.
    public static var openAppWhenRun: Bool {
        WidgetQuickExportStore.peekOpenExportReady()
    }

    public init() {}

    public func perform() async throws -> some IntentResult {
        // Flag is already set (or not) by `QuickExportIntent` before this follow-up.
        .result()
    }
}

/// Widget Export button: path A (notification + Share) with path B (open Export) when
/// notification authorization is denied.
public struct QuickExportIntent: AppIntent {
    public static var title: LocalizedStringResource = "Quick Export"
    public static var description = IntentDescription("Export this month’s hours as CSV.")

    public init() {}

    public func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let dialog = await resolveDialogAndSideEffects()
        // Single `.result` shape — always the same OpensIntent concrete type.
        return .result(
            opensIntent: OpenExportReadyIntent(),
            dialog: dialog
        )
    }

    /// Mutates store / schedules notification; returns the spoken/text dialog only.
    private func resolveDialogAndSideEffects() async -> IntentDialog {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus

        // Fallback B — denied: do not schedule a notification that will never appear.
        if status == .denied {
            WidgetQuickExportStore.markOpenExportReady()
            return "Opening Export…"
        }

        // Ask once when undetermined; if the user declines, fall through to B.
        if status == .notDetermined {
            let granted = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted != true {
                WidgetQuickExportStore.markOpenExportReady()
                return "Opening Export…"
            }
        }

        guard let snapshot = WatchSharedStore.loadSnapshot() else {
            WidgetQuickExportStore.markOpenExportReady()
            return "Open HoursTracker once to sync"
        }

        guard WidgetQuickExportStore.writeQuickCSV(from: snapshot) != nil else {
            WidgetQuickExportStore.markOpenExportReady()
            return "Export failed — opening app"
        }

        // Path A — notification share; do not set open-export flag (app stays closed).
        registerShareCategory()
        await scheduleShareNotification()
        return "Export ready — tap Share in the notification"
    }

    private func registerShareCategory() {
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

    private func scheduleShareNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "HoursTracker"
        content.body = "Your export is ready."
        content.sound = .default
        content.categoryIdentifier = WidgetQuickExportStore.notificationCategoryID
        content.userInfo = ["ht_action": "share_export"]

        let request = UNNotificationRequest(
            identifier: WidgetQuickExportStore.notificationID,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
#endif
