import SwiftUI
import HoursTrackerKit

@main
struct HoursTrackerWatchApp: App {
    @StateObject private var connectivity = WatchConnectivitySessionManager.shared

    /// Keep Kit `AppShortcutsProvider` linked so watch Siri discovers Clock In/Out.
    private let appShortcutsAnchor = HoursTrackerAppShortcuts.appShortcuts

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
                .onAppear {
                    _ = appShortcutsAnchor
                    seedScreenshotModeIfNeeded()
                    if let cached = WatchPersistenceManager.shared.load() {
                        connectivity.applyCachedSnapshot(cached)
                    }
                    // Skip live phone pairing noise in screenshot mode.
                    if !WatchScreenshotDemoData.isEnabled {
                        connectivity.activate()
                    }
                }
        }
    }

    private func seedScreenshotModeIfNeeded() {
        guard WatchScreenshotDemoData.isEnabled else { return }
        let snap = WatchScreenshotDemoData.makeSnapshot(
            language: WatchScreenshotDemoData.preferredLanguage
        )
        WatchPersistenceManager.shared.save(snap)
        connectivity.applyCachedSnapshot(snap)
    }
}
