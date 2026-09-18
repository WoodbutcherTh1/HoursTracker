import SwiftUI

@main
struct HoursTrackerWatchApp: App {
    @StateObject private var store = WatchSessionStore.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
                .onAppear { store.activate() }
        }
    }
}
