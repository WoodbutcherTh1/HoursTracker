import SwiftUI

/// Watch mirror of the phone's `MainTabView`: the same four tabs (Home, History,
/// Export, Settings), paged instead of a tab bar since that's how watchOS `TabView`
/// naturally works. Each tab wraps its content in a `NavigationStack` so the title
/// bar matches the phone's per-tab navigation title.
///
/// Language & RTL: the phone owns the language choice and echoes it back in every
/// snapshot; `WatchSessionStore.mirrorLanguage` persists it. The environment
/// locale + layout direction below re-render the whole hierarchy when the mirrored
/// language changes — Hebrew/Arabic users get a right-to-left watch app, exactly
/// like the phone.
struct WatchMainTabView: View {
    @EnvironmentObject private var store: WatchSessionStore
    @State private var selectedTab: WatchTab = .home

    private enum WatchTab: Hashable {
        case home, history, export, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { WatchHomeView() }
                .tag(WatchTab.home)

            NavigationStack { WatchHistoryView() }
                .tag(WatchTab.history)

            NavigationStack { WatchExportView() }
                .tag(WatchTab.export)

            NavigationStack { WatchSettingsView() }
                .tag(WatchTab.settings)
        }
        .tabViewStyle(.page)
        .tint(accentColor)
        .environment(\.locale, locale)
        .environment(\.layoutDirection, layoutDirection)
    }

    /// The phone's chosen Home accent color, synced via `WatchSnapshot` — every
    /// `Color.accentColor` reference across the Watch views resolves against this
    /// once it's set as the environment tint here, so the whole app matches the
    /// phone's theme instead of the watchOS system default.
    private var accentColor: Color {
        Color(hex: store.snapshot.accentColorHex)
    }

    private var locale: Locale {
        Locale(identifier: store.language.localeIdentifier)
    }

    private var layoutDirection: LayoutDirection {
        switch store.language {
        case .hebrew, .arabic: return .rightToLeft
        case .english: return .leftToRight
        }
    }
}
