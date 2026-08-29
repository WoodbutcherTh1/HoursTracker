import SwiftUI

/// The AI Assistant entry point, anchored in the top navigation bar.
///
/// Replaces the old floating/draggable button. Each tab root places it in a
/// standard `ToolbarItem` (leading slot, so it stays clear of that screen's own
/// actions), which SwiftUI mirrors automatically in RTL locales (Hebrew/Arabic)
/// and which can never cover screen content. The touch target is at least
/// 44×44pt regardless of icon size.
struct AssistantToolbarButton: View {
    let onOpen: () -> Void

    @ObservedObject private var appearance = AssistantAppearance.shared
    @ObservedObject private var theme = HomeAccentTheme.shared

    var body: some View {
        // The "Show the assistant button" toggle in the theme picker gates this:
        // when it's off the nav-bar entry point disappears from every tab root.
        if appearance.isVisible {
            Button(action: onOpen) {
                // Standard system-icon look inside the nav bar: just the symbol at
                // nav-bar scale, drawn in the app's accent color.
                Image(systemName: appearance.style.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.assistantTitle)
            .accessibilityAddTraits(.isButton)
        }
    }
}

// Each tab root adds `AssistantToolbarButton` to its own `.toolbar` in the
// `.topBarLeading` slot. Presentation is owned by `MainTabView`'s routed
// `MainSheetRoute.assistant` sheet, so there is exactly one live assistant sheet
// at any time no matter which tab opened it.
