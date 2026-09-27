import UIKit
import UserNotifications

/// Bridges home-screen quick actions (long-press app icon) into the SwiftUI
/// layer, which owns the tab state and the view model.
///
/// The URL scheme (`hourstracker://…`) already reaches SwiftUI via
/// `onOpenURL`; quick actions have no such mechanism, so this delegate maps
/// the tapped shortcut to the same deep-link URL and hands it over through
/// `AppShortcutRouting` — which both persists it (for cold launches where the
/// UI is not mounted yet) and broadcasts it (for warm launches).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        // Screenshot automation (see HoursTrackerUITests/ScreenshotTests.swift): skip the
        // first-launch onboarding cover before SwiftUI's `@AppStorage` reads the flag, so
        // there's no flash of the onboarding screen before the seeded demo data appears.
        if ProcessInfo.processInfo.arguments.contains("UITEST_SCREENSHOTS") {
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding.v1")
            // The app has its own language system (AppLanguageController), which does not
            // follow the standard `-AppleLanguages` launch argument — it must be forced
            // directly so screenshots render in English regardless of simulator/device locale.
            UserDefaults.standard.set(AppLanguageOption.english.rawValue, forKey: AppLanguageOption.storageKey)
        }
        #endif
        UNUserNotificationCenter.current().delegate = self
        ShiftReminderScheduler.registerCategories()
        // Widget buttons (clock in/out, breaks) are LiveActivityIntents that iOS runs
        // in this process — possibly a background launch with no UI — so apply them
        // straight to the shared view model instead of waiting for the app to open.
        ShiftIntentRouter.applyPending = {
            AppViewModel.shared.consumeWidgetActionIfNeeded()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let url = AppShortcutManager.url(for: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        AppShortcutRouting.route(url)
        completionHandler(true)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Without this, iOS silently drops a local notification that fires while the app
    /// is open — e.g. "your break is over" while the worker is looking at Home.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Clock In / Clock Out buttons on the shift reminders. They run without opening
    /// the app (the system launches it in the background if needed) through the same
    /// path as the in-app buttons.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        Task { @MainActor in
            let viewModel = AppViewModel.shared
            switch action {
            case ShiftReminderScheduler.clockInAction where viewModel.canClockIn:
                viewModel.clockIn()
            case ShiftReminderScheduler.clockOutAction where !viewModel.canClockIn:
                viewModel.clockOut()
            default:
                break
            }
            completionHandler()
        }
    }
}

/// Tiny routing hub for URLs that arrive before the view hierarchy exists.
enum AppShortcutRouting {
    static let didRoute = Notification.Name("htw.deepLink.route")

    /// Non-nil when a quick action fired before the UI could observe it.
    private(set) static var lastURL: URL?

    static func route(_ url: URL) {
        lastURL = url
        NotificationCenter.default.post(name: didRoute, object: url)
    }

    /// Returns and clears the pending URL (called once on view appear).
    static func consumePendingURL() -> URL? {
        defer { lastURL = nil }
        return lastURL
    }
}