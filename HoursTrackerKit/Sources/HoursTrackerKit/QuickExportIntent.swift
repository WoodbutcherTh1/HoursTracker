import AppIntents
import Foundation

#if os(iOS)
import UserNotifications
import WidgetKit

/// Opens the iPhone app on Export with a ready-to-share hand-off (fallback B).
public struct OpenExportReadyIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open Export"
    public static var description = IntentDescription("Open HoursTracker on the Export screen.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        WidgetQuickExportStore.markOpenExportReady()
        return .result()
    }
}

/// No-op follow-up so `QuickExportIntent` can return `OpensIntent` without launching the app (path A).
public struct AcknowledgeExportReadyIntent: AppIntent {
    public static var title: LocalizedStringResource = "Export Ready"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
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
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus

        // Fallback B — denied: do not schedule a notification that will never appear.
        if status == .denied {
            WidgetQuickExportStore.markOpenExportReady()
            return .result(
                opensIntent: OpenExportReadyIntent(),
                dialog: "Opening Export…"
            )
        }

        // Ask once when undetermined; if the user declines, fall through to B.
        if status == .notDetermined {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                WidgetQuickExportStore.markOpenExportReady()
                return .result(
                    opensIntent: OpenExportReadyIntent(),
                    dialog: "Opening Export…"
                )
            }
        }

        guard let snapshot = WatchSharedStore.loadSnapshot() else {
            WidgetQuickExportStore.markOpenExportReady()
            return .result(
                opensIntent: OpenExportReadyIntent(),
                dialog: "Open HoursTracker once to sync"
            )
        }

        guard WidgetQuickExportStore.writeQuickCSV(from: snapshot) != nil else {
            WidgetQuickExportStore.markOpenExportReady()
            return .result(
                opensIntent: OpenExportReadyIntent(),
                dialog: "Export failed — opening app"
            )
        }

        registerShareCategory()
        await scheduleShareNotification()
        return .result(
            opensIntent: AcknowledgeExportReadyIntent(),
            dialog: "Export ready — tap Share in the notification"
        )
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
