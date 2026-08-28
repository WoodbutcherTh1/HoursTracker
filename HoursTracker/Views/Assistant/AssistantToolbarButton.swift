import SwiftUI

/// The AI Assistant entry point, anchored in the top navigation bar.
///
/// Replaces the old floating/draggable button: standard `ToolbarItem(placement:
/// .topBarTrailing)` placement means SwiftUI mirrors it automatically in RTL
/// locales (Hebrew/Arabic) and it can never cover screen content. The touch
/// target is at least 44×44pt regardless of icon size.
struct AssistantToolbarButton: View {
    let onOpen: () -> Void

    @ObservedObject private var appearance = AssistantAppearance.shared
    @ObservedObject private var theme = HomeAccentTheme.shared

    var body: some View {
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

/// Adds the assistant entry point to a tab root's navigation bar. Presentation
/// is owned by the caller (MainTabView's routed `MainSheetRoute.assistant`
/// sheet), so there is exactly one live assistant sheet at any time.
struct AssistantToolbarEntry: ViewModifier {
    let onOpen: () -> Void
    @ObservedObject private var appearance = AssistantAppearance.shared

    func body(content: Content) -> some View {
        content.toolbar {
            if appearance.isVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    AssistantToolbarButton(onOpen: onOpen)
                }
            }
        }
    }
}

extension View {
    /// Anchors the assistant button in the top-trailing navigation bar slot.
    func assistantToolbarEntry(onOpen: @escaping () -> Void) -> some View {
        modifier(AssistantToolbarEntry(onOpen: onOpen))
    }
}
