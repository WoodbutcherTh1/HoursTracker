import SwiftUI

@main
struct HoursTrackerWatchApp: App {
    @StateObject private var store = WatchSessionStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchMainTabView()
                .environmentObject(store)
                .onAppear { store.activate() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refreshSilently() }
                }
        }
    }
}
