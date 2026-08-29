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
                    // Remount tabs when language changes so UIKit tab items + L10n
                    // strings refresh. Keep this off the splash/`@State` so changing
                    // language does not replay the launch animation.
                    .id(appLanguage.preference)

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
            // HoursTracker is a dark app: Home, the payslip screens, the lock screen and
            // the splash have always painted their own dark surface regardless of the
            // device appearance. History, Export and Settings used to follow the system
            // instead, so a phone in light mode got a half-light app. Pinning the scheme
            // makes the whole thing consistent and lets AppBackgroundTheme's color show
            // through on every screen, which is the point of the background picker.
            .preferredColorScheme(.dark)
            .environmentObject(appLock)
            .environmentObject(appLanguage)
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

/// The two sheets a `MainTabView` can show at its own level (as opposed to inside a
/// single tab). Kept as one routed sheet rather than two independent
/// `.sheet(isPresented:)` modifiers on the same `TabView`: `showPendingScannerReview`
/// flips `true` from inside a background `Task` the instant a scan finishes, entirely
/// independent of whatever the user is doing — including with the assistant chat already
/// open, since both are reachable from every tab. Two simultaneously-live sheets on one
/// view is a documented SwiftUI conflict (at most one can actually present), so unifying
/// them here removes the race outright rather than leaving it to be discovered live.
private enum MainSheetRoute: Identifiable, Hashable {
    case assistant
    case scannerReview

    var id: Self { self }
}

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var appLanguage: AppLanguageController
    // The Home screen's color picker is app-wide: this drives the tab bar's selected
    // color and every standard button/toggle/link tint across History, Export, and
    // Settings, not just Home's own neon-styled elements.
    @ObservedObject private var homeTheme = HomeAccentTheme.shared

    /// A scan that completes while the assistant is already open stays queued rather
    /// than yanking the assistant away mid-conversation: the existing "ready for review"
    /// banner (below) already reappears the moment the assistant closes, since clearing
    /// the route resets `showPendingScannerReview` back to false and its guard condition
    /// is keyed on exactly that flag. Nothing is lost — the user just finishes what they
    /// were doing first.
    private var activeSheetRoute: Binding<MainSheetRoute?> {
        Binding(
            get: {
                if viewModel.showAssistant { return .assistant }
                if viewModel.showPendingScannerReview { return .scannerReview }
                return nil
            },
            set: { newRoute in
                viewModel.showAssistant = (newRoute == .assistant)
                viewModel.showPendingScannerReview = (newRoute == .scannerReview)
            }
        )
    }

    var body: some View {
        let _ = appLanguage.preference // keep tab labels tied to language changes
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
        .tint(homeTheme.accent)
        // The assistant lives in each tab root's navigation bar now
        // (`AssistantToolbarButton` in the leading slot), so there is no floating
        // overlay to cover screen content. Below the toast, so a confirmation
        // banner is never hidden behind anything.
        .overlay(alignment: .bottom) {
            if let message = viewModel.successToast {
                SuccessToastBanner(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 56)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.successToast)
        // A single routed sheet — see `MainSheetRoute` — rather than one
        // `.sheet(isPresented:)` per case, so the assistant and the scanner-review sheet
        // (which a background scan can request at any moment) can never both be live at
        // once and fight over which actually presents.
        .sheet(item: activeSheetRoute) { route in
            switch route {
            case .assistant:
                AssistantChatSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .scannerReview:
                // `pendingScannerResult` is deliberately left set after this sheet closes
                // — Keep result until import commits or user explicitly clears — so the
                // "ready for review" banner below can still reopen it later.
                if let result = viewModel.pendingScannerResult {
                    TimesheetScannerView(appViewModel: viewModel, initialResult: result)
                }
            }
        }
        .overlay(alignment: .top) {
            if case .processing = viewModel.scannerImportPhase {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.scannerAnalyzing)
                        .font(.footnote.weight(.medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.scannerAnalyzing)
            } else if case .ready = viewModel.scannerImportPhase, !viewModel.showPendingScannerReview {
                Button {
                    viewModel.openPendingScannerReview()
                } label: {
                    Label(L10n.scannerReadyForReview, systemImage: "doc.text.magnifyingglass")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
    }
}
