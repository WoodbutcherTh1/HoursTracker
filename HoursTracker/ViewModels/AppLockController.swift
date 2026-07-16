import Foundation
import SwiftUI
import Combine

@MainActor
final class AppLockController: ObservableObject {
    @Published private(set) var isLocked: Bool
    @Published private(set) var authErrorMessage: String?
    @Published var isEnabled: Bool {
        didSet {
            preference.isEnabled = isEnabled
            if !isEnabled {
                isLocked = false
                authErrorMessage = nil
                backgroundedAt = nil
            }
        }
    }

    private let preference: AppLockPreferencing
    private let authenticator: BiometricAuthenticating
    private var backgroundedAt: Date?

    init(
        preference: AppLockPreferencing = UserDefaultsAppLockPreference.shared,
        authenticator: BiometricAuthenticating = LocalAuthenticationService()
    ) {
        self.preference = preference
        self.authenticator = authenticator
        let enabled = preference.isEnabled
        self.isEnabled = enabled
        // Locked on launch when the feature is on.
        self.isLocked = enabled
    }

    func handleScenePhase(_ phase: ScenePhase, now: Date = Date()) {
        switch phase {
        case .background:
            backgroundedAt = now
        case .active:
            if AppLockPolicy.shouldLockOnResume(
                isEnabled: isEnabled,
                backgroundedAt: backgroundedAt,
                now: now
            ) {
                isLocked = true
            }
            // Clear stamp after evaluating so short inactive blips after unlock
            // don't immediately re-lock without a real backgrounding.
            if !isLocked {
                backgroundedAt = nil
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func unlock() async {
        guard isEnabled else {
            isLocked = false
            return
        }
        authErrorMessage = nil
        do {
            let success = try await authenticator.authenticate(reason: L10n.appLockReason)
            if success {
                isLocked = false
                backgroundedAt = nil
            } else {
                authErrorMessage = L10n.appLockFailed
            }
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }
}
