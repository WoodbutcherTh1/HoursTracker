import Foundation

/// A locally-generated `HT-XXXXX` ID shown in the Settings profile card, generated
/// once per install and persisted so it doesn't change between launches.
///
/// This is a **placeholder**, not the real public user ID: the real one is meant
/// to be issued and owned by the backend (one per Supabase profile, looked up by
/// admins), which this app doesn't talk to yet for this feature. When that lands,
/// swap this read for the server-issued value — the display/copy UI in
/// `SettingsView` is already wired to whatever this returns, so no UI changes
/// should be needed there, only the source of the string.
enum LocalPlaceholderUserID {
    private static let storageKey = "localPlaceholderUserID"
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // no 0/O/1/I

    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: storageKey) {
            return existing
        }
        let suffix = String((0..<5).map { _ in alphabet.randomElement()! })
        let id = "HT-\(suffix)"
        defaults.set(id, forKey: storageKey)
        return id
    }
}
