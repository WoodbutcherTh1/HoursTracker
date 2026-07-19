import SwiftUI
import HoursTrackerKit

struct ContentView: View {
    @EnvironmentObject private var connectivity: WatchConnectivitySessionManager
    @StateObject private var viewModel = WatchAppViewModel()

    var body: some View {
        NavigationStack {
            ClockScreenView(viewModel: viewModel)
                .toolbar {
                    // Always trailing: in RTL, trailing mirrors to the visual left.
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            RecentShiftsView(viewModel: viewModel)
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityIdentifier("watch.nav.recent")
                    }
                }
        }
        .environment(\.locale, viewModel.locale)
        .environment(\.layoutDirection, viewModel.layoutDirection)
        // Force remount when screenshot language changes so RTL + strings apply.
        .id(viewModel.paySettings.language)
        .onChange(of: connectivity.isPhoneReachable) { _, _ in
            viewModel.refreshReachability()
        }
        .onChange(of: connectivity.snapshot) { _, snap in
            // Connectivity manager already invokes onSnapshot; this keeps UI
            // in sync if the published snapshot changes without a callback race.
            if snap != nil {
                viewModel.refreshReachability()
            }
        }
        .onOpenURL { url in
            // Complications deep-link here; Clock is already the root screen.
            _ = url
        }
        .task {
            viewModel.ensureScreenshotDemoIfNeeded()

            // Manual matrix helper: `HT_MATRIX_ACTION=clockIn|clockOut|toggle`
            // via simctl launch — avoids XCTest reinstall wiping the queue.
            let action: String? = {
                if let env = ProcessInfo.processInfo.environment["HT_MATRIX_ACTION"], !env.isEmpty {
                    return env
                }
                let args = ProcessInfo.processInfo.arguments
                if let eq = args.first(where: { $0.hasPrefix("HT_MATRIX_ACTION=") }) {
                    return String(eq.split(separator: "=").last ?? "")
                }
                if let idx = args.firstIndex(of: "HT_MATRIX_ACTION"),
                   args.index(after: idx) < args.endIndex {
                    return args[args.index(after: idx)]
                }
                return nil
            }()
            guard let action, !action.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            switch action {
            case "clockIn":
                if viewModel.canClockIn { viewModel.clockIn() }
            case "clockOut":
                if viewModel.isClockedIn { viewModel.clockOut() }
            case "toggle":
                viewModel.toggleClock()
            default:
                break
            }
            try? await Task.sleep(for: .milliseconds(800))
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivitySessionManager.shared)
}
