import SwiftUI

@main
struct HoursTrackerWatchApp: App {
    @StateObject private var store = WatchSessionStore.shared

    var body: some Scene {
        WindowGroup {
            WatchMainTabView()
                .environmentObject(store)
                .onAppear { store.activate() }
        }
    }
}
