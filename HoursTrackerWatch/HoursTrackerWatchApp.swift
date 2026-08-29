import SwiftUI

@main
struct HoursTrackerWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            ContentView(connectivity: connectivity)
        }
    }
}
