import Foundation

/// The user's agreement to the Terms of Use and the Privacy Policy.
///
/// Until the current version is accepted the app shows `LegalConsentView` over
/// everything (onboarding included) and nothing else can be used. Bump
/// `currentVersion` whenever the terms or the policy change in a meaningful way:
/// every user, new or existing, is then asked to agree again.
@MainActor
final class LegalConsent: ObservableObject {
    static let shared = LegalConsent()

    /// 1 = terms + policy of 29 Sep 2026 (first version with a consent screen).
    static let currentVersion = 1

    static let versionKey = "legal.acceptedVersion"
    static let dateKey = "legal.acceptedAt"
    /// UI tests that exercise the consent screen itself.
    static let uiTestArgument = "UITEST_LEGAL_CONSENT"

    @Published private(set) var acceptedVersion: Int
    @Published private(set) var acceptedAt: Date?

    private let defaults: UserDefaults
    private let skipsGate: Bool

    init(defaults: UserDefaults = .standard, skipsGate: Bool = LegalConsent.isAutomatedRunWithoutConsentTest) {
        self.defaults = defaults
        self.skipsGate = skipsGate
        acceptedVersion = defaults.integer(forKey: Self.versionKey)
        let stamp = defaults.double(forKey: Self.dateKey)
        acceptedAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// True once the current terms were accepted (always true in automated test
    /// runs, except the consent screen's own UI test).
    var isAccepted: Bool {
        skipsGate || acceptedVersion >= Self.currentVersion
    }

    /// True when an earlier version was accepted, so the screen says "updated".
    var isReconsent: Bool {
        acceptedVersion > 0 && acceptedVersion < Self.currentVersion
    }

    func accept(now: Date = Date()) {
        acceptedVersion = Self.currentVersion
        acceptedAt = now
        defaults.set(Self.currentVersion, forKey: Self.versionKey)
        defaults.set(now.timeIntervalSince1970, forKey: Self.dateKey)
        ActivityLogStore.shared.log(
            "Accepted terms and privacy policy",
            level: .info,
            category: "legal",
            details: "v\(Self.currentVersion)"
        )
    }

    nonisolated static var isAutomatedRunWithoutConsentTest: Bool {
        let info = ProcessInfo.processInfo
        let automated = info.environment["XCTestConfigurationFilePath"] != nil
            || info.arguments.contains { $0.hasPrefix("UITEST_") }
        return automated && !info.arguments.contains(uiTestArgument)
    }
}
