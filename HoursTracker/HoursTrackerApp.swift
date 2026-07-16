import SwiftUI

@main
struct HoursTrackerApp: App {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var appLock = AppLockController()
    @ObservedObject private var appLanguage = AppLanguageController.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLaunchSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView(viewModel: viewModel)
                    .keyboardDismissible()

                if appLock.isEnabled && appLock.isLocked {
                    AppLockView(controller: appLock)
                        .transition(.opacity)
                }

                // Always redact for app-switcher snapshots, regardless of App Lock.
                if scenePhase != .active {
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
            .environmentObject(appLock)
            .environmentObject(appLanguage)
            .id(appLanguage.preference)
            .onAppear {
                ExportTempFileStore.wipeAll()
                viewModel.syncNow()
                KeyboardTapDismissInstaller.shared.installIfNeeded()
                if appLock.isEnabled {
                    Task { await appLock.unlock() }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(2100))
                    showLaunchSplash = false
                }
            }
            .onChange(of: scenePhase) { _, phase in
                appLock.handleScenePhase(phase)
                // Wipe on background only — `.inactive` also fires while the share
                // sheet is presented and would delete the file mid-share.
                if phase == .active {
                    viewModel.syncNow()
                    if appLock.isEnabled && appLock.isLocked {
                        Task { await appLock.unlock() }
                    }
                } else if phase == .background {
                    ExportTempFileStore.wipeAll()
                }
            }
        }
    }
}

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            HomeView(viewModel: viewModel)
                .tabItem {
                    Label(L10n.tabHome, systemImage: "clock.fill")
                }
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
                .tabItem {
                    Label(L10n.tabHistory, systemImage: "list.bullet.rectangle")
                }

            ExportView(viewModel: viewModel)
                .tabItem {
                    Label(L10n.tabExport, systemImage: "square.and.arrow.up")
                }

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label(L10n.tabSettings, systemImage: "gearshape.fill")
                }
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
