import AppIntents
import Foundation

#if os(iOS)
import UserNotifications
import WidgetKit

/// Opens the iPhone app on Export (Shortcuts / hand-off).
/// `openAppWhenRun` must be a **literal** `true`/`false` — App Intents rejects computed values.
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

/// Widget Export: path A = notification Share (stay in widget); path B = open host Export tab.
///
/// Uses `ForegroundContinuableIntent` so path B can open the app **without** returning
/// a second `OpensIntent` type (which breaks opaque `some` returns) and **without**
/// a computed `openAppWhenRun` (which App Intents metadata rejects).
public struct QuickExportIntent: AppIntent, ForegroundContinuableIntent {
    public static var title: LocalizedStringResource = "Quick Export"
    public static var description = IntentDescription("Export this month’s hours as CSV.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await Self.resolveOutcome()

        if outcome.shouldOpenApp {
            // Path B — continue into the host app (flag already set for Export hand-off).
            try await requestToContinueInForeground()
        }

        return .result(dialog: IntentDialog(stringLiteral: outcome.message))
    }

    private struct Outcome: Sendable {
        var message: String
        var shouldOpenApp: Bool
    }

    /// All branching returns the same `Outcome` shape (no mixed intent results here).
    private static func resolveOutcome() async -> Outcome {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus

        if status == .denied {
            WidgetQuickExportStore.markOpenExportReady()
            return Outcome(message: "Opening Export…", shouldOpenApp: true)
        }

        if status == .notDetermined {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if !granted {
                WidgetQuickExportStore.markOpenExportReady()
                return Outcome(message: "Opening Export…", shouldOpenApp: true)
            }
        }

        guard let snapshot = WatchSharedStore.loadSnapshot() else {
            WidgetQuickExportStore.markOpenExportReady()
            return Outcome(message: "Open HoursTracker once to sync", shouldOpenApp: true)
        }

        guard WidgetQuickExportStore.writeQuickCSV(from: snapshot) != nil else {
            WidgetQuickExportStore.markOpenExportReady()
            return Outcome(message: "Export failed — opening app", shouldOpenApp: true)
        }

        Self.registerShareCategory()
        await Self.scheduleShareNotification()
        return Outcome(
            message: "Export ready — tap Share in the notification",
            shouldOpenApp: false
        )
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
