import SwiftUI

/// User-replaceable text for the Home screen wordmark (the "HoursTracker" title in the
/// Home navigation bar). Scope is deliberately just that one label — the tab bar, sheets,
/// exports, and `L10n.brandName` everywhere else keep the real product name.
///
/// Same shape as `HomeAccentTheme`: one `@Published` value mirrored into `UserDefaults`
/// on every set, plus a `reset()` back to the shipped default.
///
/// Note for anyone wiring this up further: this cannot change the app's Home Screen icon
/// label. That comes from `CFBundleDisplayName`, which is fixed at build time — iOS gives
/// an app no way to rewrite it from inside itself.
@MainActor
final class HomeWordmark: ObservableObject {
    static let shared = HomeWordmark()

    private static let storageKey = "homeWordmarkText"
    /// Longer than this and the nav bar title starts truncating on an SE-class screen.
    static let maxLength = 24

    /// Empty means "use the built-in two-tone HoursTracker mark" — that's the default,
    /// so nothing changes until the user actually types something.
    @Published var text: String {
        didSet {
            let normalized = Self.normalize(text)
            if normalized != text {
                // Assigning inside `didSet` intentionally does not re-enter it, so the
                // persist below has to use `normalized` rather than re-reading `text`.
                text = normalized
            }
            UserDefaults.standard.set(normalized, forKey: Self.storageKey)
        }
    }

    private init(defaults: UserDefaults = .standard) {
        text = Self.normalize(defaults.string(forKey: Self.storageKey) ?? "")
    }

    /// The custom mark to draw, or `nil` when the built-in one should be used.
    var customText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isCustomized: Bool { customText != nil }

    func reset() {
        text = ""
    }

    /// Collapses newlines (a paste can carry them) and caps the length so the title
    /// can't push the toolbar buttons off-screen.
    static func normalize(_ raw: String) -> String {
        let flattened = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(flattened.prefix(maxLength))
    }
}
