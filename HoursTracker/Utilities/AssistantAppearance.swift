import SwiftUI

/// Icon choices for the assistant entry point in the navigation bar. All SF
/// Symbols, all drawn in the app's own accent color rather than some generic
/// "AI" purple — the assistant is part of HoursTracker, not a guest in it.
enum AssistantIconStyle: String, CaseIterable, Identifiable, Codable {
    case spark
    case chat
    case clock
    case wand

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .spark: return "sparkles"
        case .chat: return "bubble.left.and.text.bubble.right.fill"
        case .clock: return "clock.badge.questionmark.fill"
        case .wand: return "wand.and.stars"
        }
    }

    var title: String {
        switch self {
        case .spark: return L10n.assistantStyleSpark
        case .chat: return L10n.assistantStyleChat
        case .clock: return L10n.assistantStyleClock
        case .wand: return L10n.assistantStyleWand
        }
    }
}

/// Visibility and icon for the assistant toolbar button.
///
/// Same pattern as `HomeAccentTheme` and `HomeStatsLayout`: `@Published` values mirrored
/// into `UserDefaults` on set, so hiding the button or picking an icon survives relaunch
/// without any explicit save step. (The old floating button's edge/vertical-offset state
/// is gone along with the drag gesture that used it.)
@MainActor
final class AssistantAppearance: ObservableObject {
    static let shared = AssistantAppearance()

    private enum Key {
        static let enabled = "assistantButtonEnabled"
        static let style = "assistantButtonStyle"
    }

    @Published var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: Key.enabled) }
    }

    @Published var style: AssistantIconStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Key.style) }
    }

    private init(defaults: UserDefaults = .standard) {
        isVisible = defaults.object(forKey: Key.enabled) as? Bool ?? true
        style = (defaults.string(forKey: Key.style)).flatMap(AssistantIconStyle.init(rawValue:))
            ?? .spark
    }
}
