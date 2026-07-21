import SwiftUI
import HoursTrackerKit

@main
struct HoursTrackerApp: App {
    @UIApplicationDelegateAdaptor(HoursTrackerAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var appLock = AppLockController()
    @ObservedObject private var appLanguage = AppLanguageController.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLaunchSplash = true
    @State private var selectedTab: MainTab = .home

    private var isScreenshotMode: Bool { PhoneScreenshotDemoData.isEnabled }

    /// Keep Kit `AppShortcutsProvider` linked so Siri discovers Clock In/Out on iPhone.
    private let appShortcutsAnchor = HoursTrackerAppShortcuts.appShortcuts

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView(viewModel: viewModel, selectedTab: $selectedTab)
                    .keyboardDismissible()
                    // Remount tabs when language changes so UIKit tab items + L10n
                    // strings refresh. Keep this off the splash/`@State` so changing
                    // language does not replay the launch animation.
                    .id(appLanguage.preference)
                    .onAppear {
                        _ = appShortcutsAnchor
                    }

                if !isScreenshotMode && appLock.isEnabled && appLock.isLocked {
                    AppLockView(controller: appLock)
                        .transition(.opacity)
                }

                // Always redact for app-switcher snapshots, regardless of App Lock.
                if !isScreenshotMode && scenePhase != .active {
                    PrivacyOverlayView()
                        .transition(.opacity)
                }

                if showLaunchSplash {
                    LaunchHourglassSplash()
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appLock.isLocked)
            .animation(.easeInOut(duration: 0.15), value: scenePhase)
            .animation(.easeInOut(duration: 0.45), value: showLaunchSplash)
            .environment(\.locale, appLanguage.locale)
            .environment(\.layoutDirection, appLanguage.layoutDirection)
            // Marketing captures: force dark for ALL tabs (Home neon + History/Export/
            // Settings system chrome). Light would make Home vs other tabs inconsistent.
            .preferredColorScheme(isScreenshotMode ? .dark : nil)
            .environmentObject(appLock)
            .environmentObject(appLanguage)
            .onAppear {
                ExportTempFileStore.wipeAll()
                AppNotificationCenter.shared.install()
                AppNotificationCenter.shared.onShareExport = {
                    viewModel.presentShareFromQuickExportIfNeeded()
                    selectedTab = .export
                }
                if !isScreenshotMode {
                    viewModel.syncNow()
                }
                KeyboardTapDismissInstaller.shared.installIfNeeded()
                if !isScreenshotMode && appLock.isEnabled {
                    Task { await appLock.unlock() }
                }
                Task { @MainActor in
                    // Short splash in screenshot/preview mode so recording can start sooner.
                    let splashMs: UInt64 = isScreenshotMode ? 400 : 2100
                    try? await Task.sleep(for: .milliseconds(splashMs))
                    showLaunchSplash = false
                    handleExportHandoffs()
                }
                // Manual matrix: simctl -e HT_MATRIX_ACTION=clockIn|clockOut|toggle
                Task { @MainActor in
                    let action: String? = {
                        if let env = ProcessInfo.processInfo.environment["HT_MATRIX_ACTION"], !env.isEmpty {
                            return env
                        }
                        // argv forms: HT_MATRIX_ACTION=clockIn  OR  clockIn after that key
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
                    // Wait for splash + store load.
                    try? await Task.sleep(for: .milliseconds(2300))
                    switch action {
                    case "clockIn":
                        if viewModel.canClockIn { viewModel.clockIn() }
                    case "clockOut":
                        if viewModel.isClockedIn { viewModel.clockOut() }
                    case "toggle":
                        if viewModel.isClockedIn { viewModel.clockOut() }
                        else if viewModel.canClockIn { viewModel.clockIn() }
                    default:
                        break
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                appLock.handleScenePhase(phase)
                // Wipe on background only — `.inactive` also fires while the share
                // sheet is presented and would delete the file mid-share.
                if phase == .active {
                    viewModel.syncNow()
                    handleExportHandoffs()
                    if appLock.isEnabled && appLock.isLocked {
                        Task { await appLock.unlock() }
                    }
                } else if phase == .background {
                    ExportTempFileStore.wipeAll()
                }
            }
            .onChange(of: viewModel.pendingOpenExportReady) { _, ready in
                if ready {
                    selectedTab = .export
                }
            }
            .onOpenURL { url in
                handleOpenURL(url)
            }
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard url.scheme == "hourstracker" else { return }
        if url.host == "export" {
            WidgetQuickExportStore.markOpenExportReady()
            viewModel.pendingOpenExportReady = true
            selectedTab = .export
        }
    }

    private func handleExportHandoffs() {
        viewModel.reconcileSharedSurfaces()
        if viewModel.pendingOpenExportReady {
            selectedTab = .export
        }
        if viewModel.pendingShareExportURL != nil {
            selectedTab = .export
        }
    }
}

enum MainTab: Hashable {
    case home
    case history
    case export
    case settings
}

final class HoursTrackerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppNotificationCenter.shared.install()
        return true
    }
}

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selectedTab: MainTab
    @EnvironmentObject private var appLanguage: AppLanguageController

    var body: some View {
        let _ = appLanguage.preference // keep tab labels tied to language changes
        TabView(selection: $selectedTab) {
            HomeView(viewModel: viewModel)
                .accessibilityIdentifier("phone.tab.home")
                .tabItem {
                    Label(L10n.tabHome, systemImage: "clock.fill")
                }
                .tag(MainTab.home)
                .alert(
                    L10n.errorTitle,
                    isPresented: Binding(
                        get: { viewModel.errorMessage != nil },
                        set: { if !$0 { viewModel.errorMessage = nil } }
                    )
                ) {
                    Button(L10n.errorOK, role: .cancel) {
                        viewModel.errorMessage = nil
                    }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }

            HistoryView(viewModel: viewModel)
                .accessibilityIdentifier("phone.tab.history")
                .tabItem {
                    Label(L10n.tabHistory, systemImage: "list.bullet.rectangle")
                }
                .tag(MainTab.history)

            ExportView(viewModel: viewModel)
                .accessibilityIdentifier("phone.tab.export")
                .tabItem {
                    Label(L10n.tabExport, systemImage: "square.and.arrow.up")
                }
                .tag(MainTab.export)

            SettingsView(viewModel: viewModel)
                .accessibilityIdentifier("phone.tab.settings")
                .tabItem {
                    Label(L10n.tabSettings, systemImage: "gearshape.fill")
                }
                .tag(MainTab.settings)
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.successToast {
                SuccessToastBanner(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 56)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.successToast)
    }
}
