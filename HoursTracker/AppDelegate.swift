import UIKit

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