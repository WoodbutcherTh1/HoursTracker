import Foundation

/// User-facing opt-in for uploading to the private iCloud database.
/// Default is off so CloudKit-enabled builds never sync without explicit consent.
protocol CloudSyncPreferencing: AnyObject {
    var isEnabled: Bool { get set }
}

/// Persists the toggle in UserDefaults (reason code CA92.1 to be declared in Phase 3 privacy manifest).
final class UserDefaultsCloudSyncPreference: CloudSyncPreferencing {
    static let shared = UserDefaultsCloudSyncPreference()
    static let storageKey = "iCloudSyncEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.storageKey) }
        set { defaults.set(newValue, forKey: Self.storageKey) }
    }
}
