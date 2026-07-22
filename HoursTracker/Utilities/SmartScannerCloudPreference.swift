import Foundation

/// Opt-in for sending OCR text to a cloud LLM during Smart Scanner.
/// Default is off — local heuristic only until the user enables it.
protocol SmartScannerCloudPreferencing: AnyObject {
    var isEnabled: Bool { get set }
}

/// Persists the toggle in UserDefaults (declared as CA92.1 in PrivacyInfo.xcprivacy).
final class UserDefaultsSmartScannerCloudPreference: SmartScannerCloudPreferencing {
    static let shared = UserDefaultsSmartScannerCloudPreference()
    static let storageKey = "smartScannerCloudEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.storageKey) }
        set { defaults.set(newValue, forKey: Self.storageKey) }
    }
}
