import AppIntents
import Foundation

#if os(iOS)
import UserNotifications
import WidgetKit

/// Opens the iPhone app on Export (Shortcuts / hand-off). Also used when
/// `QuickExportIntent` sets the App Group flag and `openAppWhenRun` becomes true.
public struct OpenExportReadyIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open Export"
    public static var description = IntentDescription("Open HoursTracker on the Export screen.")

    public static var openAppWhenRun: Bool {
        WidgetQuickExportStore.peekOpenExportReady()
    }

    public init() {}

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Widget Export button: path A (notification + Share) with path B (open Export) when
/// notification authorization is denied.
///
/// Important: a single `return .result(dialog:)` only — never mix `OpensIntent`
/// follow-ups of different concrete types (that breaks opaque `some` returns).
public struct QuickExportIntent: AppIntent {
    public static var title: LocalizedStringResource = "Quick Export"
    public static var description = IntentDescription("Export this month’s hours as CSV.")

    /// Read **after** `perform()` side effects. Path B sets the App Group flag first;
    /// the system then opens the host app. Path A leaves the flag clear.
    public static var openAppWhenRun: Bool {
        WidgetQuickExportStore.peekOpenExportReady()
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message: String = await Self.resolveMessageAndSideEffects()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }

    /// All branching lives here and returns `String` only (same type on every path).
    private static func resolveMessageAndSideEffects() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus

        if status == .denied {
            WidgetQuickExportStore.markOpenExportReady()
            return "Opening Export…"
        }

        if status == .notDetermined {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if !granted {
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

        Self.registerShareCategory()
        await Self.scheduleShareNotification()
        return "Export ready — tap Share in the notification"
    }

    private static func registerShareCategory() {
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

    private static func scheduleShareNotification() async {
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
