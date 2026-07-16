import Foundation
import LocalAuthentication

protocol BiometricAuthenticating {
    func authenticate(reason: String) async throws -> Bool
}

enum AppLockAuthError: LocalizedError {
    case unavailable
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable: return L10n.appLockUnavailable
        case .failed: return L10n.appLockFailed
        }
    }
}

/// Uses LocalAuthentication only — never stores secrets.
struct LocalAuthenticationService: BiometricAuthenticating {
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = L10n.editCancel
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? AppLockAuthError.unavailable
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            throw AppLockAuthError.failed
        }
    }
}
