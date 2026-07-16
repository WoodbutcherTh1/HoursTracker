import SwiftUI

@main
struct HoursTrackerApp: App {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView(viewModel: viewModel)
                .keyboardDismissible()
                .onAppear {
                    ExportTempFileStore.wipeAll()
                    viewModel.syncNow()
                    KeyboardTapDismissInstaller.shared.installIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Wipe on background only — `.inactive` also fires while the share
                    // sheet is presented and would delete the file mid-share.
                    if phase == .active {
                        viewModel.syncNow()
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
