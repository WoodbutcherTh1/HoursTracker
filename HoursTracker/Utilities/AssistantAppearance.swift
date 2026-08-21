import SwiftUI

/// Which side of the screen the floating assistant button rests against.
enum AssistantIconEdge: String, CaseIterable, Codable {
    case leading
    case trailing

    var alignment: Alignment {
        self == .leading ? .bottomLeading : .bottomTrailing
    }
}

/// Icon choices for the floating button. All SF Symbols, all drawn in the app's own
/// accent color rather than some generic "AI" purple — the assistant is part of
/// HoursTracker, not a guest in it.
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

/// Visibility, position and icon for the floating assistant button.
///
/// Same pattern as `HomeAccentTheme` and `HomeStatsLayout`: `@Published` values mirrored
/// into `UserDefaults` on set, so a drag or a hide survives relaunch without any explicit
/// save step.
@MainActor
final class AssistantAppearance: ObservableObject {
    static let shared = AssistantAppearance()

    private enum Key {
        static let enabled = "assistantButtonEnabled"
        static let edge = "assistantButtonEdge"
        static let offset = "assistantButtonVerticalOffset"
        static let style = "assistantButtonStyle"
    }

    /// Default side is leading. In the RTL languages this app is mostly used in, the
    /// thumb that works the tab bar sits on the trailing side, so the button starts out
    /// of its way — and it is draggable anyway for anyone who disagrees.
    static let defaultEdge: AssistantIconEdge = .leading
    /// 0 = just above the tab bar, 1 = just below the navigation bar.
    static let defaultVerticalOffset: Double = 0.22

    @Published var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: Key.enabled) }
    }

    @Published var edge: AssistantIconEdge {
        didSet { UserDefaults.standard.set(edge.rawValue, forKey: Key.edge) }
    }

    /// Fraction of the usable height, measured up from the bottom. Clamped on set so a
    /// drag can never park the button off-screen or under the tab bar.
    @Published var verticalOffset: Double {
        didSet {
            let clamped = min(max(verticalOffset, 0), 1)
            if clamped != verticalOffset {
                // Assigning in `didSet` deliberately doesn't re-enter it, so persist the
                // clamped value here rather than re-reading the property.
                verticalOffset = clamped
            }
            UserDefaults.standard.set(clamped, forKey: Key.offset)
        }
    }

    @Published var style: AssistantIconStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Key.style) }
    }

    private init(defaults: UserDefaults = .standard) {
        isVisible = defaults.object(forKey: Key.enabled) as? Bool ?? true
        edge = (defaults.string(forKey: Key.edge)).flatMap(AssistantIconEdge.init(rawValue:))
            ?? Self.defaultEdge
        let savedOffset = defaults.object(forKey: Key.offset) as? Double
        verticalOffset = min(max(savedOffset ?? Self.defaultVerticalOffset, 0), 1)
        style = (defaults.string(forKey: Key.style)).flatMap(AssistantIconStyle.init(rawValue:))
            ?? .spark
    }

    func resetPosition() {
        edge = Self.defaultEdge
        verticalOffset = Self.defaultVerticalOffset
    }
}
