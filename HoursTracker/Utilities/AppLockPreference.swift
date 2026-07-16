import Foundation

protocol AppLockPreferencing: AnyObject {
    var isEnabled: Bool { get set }
}

/// Opt-in App Lock flag (default off). Stored in UserDefaults (CA92.1).
final class UserDefaultsAppLockPreference: AppLockPreferencing {
    static let shared = UserDefaultsAppLockPreference()
    static let storageKey = "appLockEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.storageKey) }
        set { defaults.set(newValue, forKey: Self.storageKey) }
    }
}

enum AppLockPolicy {
    static let gracePeriod: TimeInterval = 30

    /// Whether returning from a backgrounded state should require authentication.
    /// Cold start locking is handled separately by `AppLockController` init.
    static func shouldLockOnResume(
        isEnabled: Bool,
        backgroundedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard isEnabled, let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= gracePeriod
    }

    /// Redacts all but the last 4 characters of an ID for Settings display.
    static func maskedNationalID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "••••" }
        if trimmed.count <= 4 {
            return String(repeating: "•", count: trimmed.count)
        }
        let suffix = trimmed.suffix(4)
        return String(repeating: "•", count: trimmed.count - 4) + suffix
    }
}
