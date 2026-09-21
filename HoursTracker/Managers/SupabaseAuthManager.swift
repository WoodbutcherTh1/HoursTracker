import Foundation
import os
import Supabase

/// Errors surfaced to the sign-up / sign-in screens, already carrying a
/// localized message so the UI never has to interpret a raw SDK error.
enum AccountAuthError: LocalizedError {
    case nameRequired
    case invalidEmail
    case passwordTooShort
    case codeIncomplete
    case codeExpired
    case notSignedUpYet
    case server(String)

    var errorDescription: String? {
        switch self {
        case .nameRequired: return L10n.accountErrorNameRequired
        case .invalidEmail: return L10n.accountErrorInvalidEmail
        case .passwordTooShort: return L10n.accountErrorPasswordTooShort
        case .codeIncomplete: return L10n.accountErrorCodeIncomplete
        case .codeExpired:
            // GoTrue reports wrong, already-used, and genuinely expired codes
            // identically, so don't claim outright that the code expired.
            return L10n.accountErrorCodeExpired
        case .notSignedUpYet: return L10n.accountErrorNotSignedUpYet
        case .server(let message): return message
        }
    }
}

/// Account identity: sign-up, email-code verification, and sign-in against
/// the HoursTracker Supabase project. Session storage (Keychain) is handled
/// entirely by the SDK, so `isSignedIn` survives app restarts automatically —
/// that's what makes "sign out and back in" or "reinstall" restore the
/// account without any extra work here.
///
/// Data sync (uploading/downloading the actual shifts + settings) is a
/// separate concern — see `SupabaseAccountSyncManager`. This type only
/// answers "who is signed in," never touches `work_sessions`/`profiles` rows.
@MainActor
final class SupabaseAuthManager: ObservableObject {
    static let shared = SupabaseAuthManager()

    private static let logger = Logger(subsystem: "com.hourstracker.app", category: "auth")

    let client: SupabaseClient

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var currentUserID: UUID?
    @Published private(set) var currentEmail: String?
    /// When the signed-in account was created (Account screen "member since").
    @Published private(set) var currentUserCreatedAt: Date?

    private var authStateTask: Task<Void, Never>?

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.publishableKey,
            options: .init(
                // Opt-in to the corrected initial-session behavior (PR #822): the
                // locally stored session is emitted immediately as `.initialSession`
                // instead of after a network refresh attempt. This silences the
                // SDK's runtime warning and makes startup deterministic — no
                // refresh request is required before the UI knows who's signed in.
                // The trade-off, per the SDK docs: the emitted session can be
                // expired, so `handle(event:session:)` must check
                // `session.isExpired` before trusting it.
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
        let session = client.auth.currentSession
        isSignedIn = session != nil
        currentUserID = session?.user.id
        currentEmail = session?.user.email
        currentUserCreatedAt = session?.user.createdAt

        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                self.handle(event: event, session: session)
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    private func handle(event: AuthChangeEvent, session: Session?) {
        // With `emitLocalSessionAsInitialSession: true` the SDK emits the locally
        // stored session verbatim, possibly already expired. A stale session is
        // not a sign-in: treat it as signed out and let the SDK's auto-refresh
        // either renew it (a later `.tokenRefreshed` flips us back) or the user
        // simply signs in again. Without this guard the app would show a signed-in
        // UI backed by a dead token and every request would 401.
        let effectiveSession: Session?
        if let session, session.isExpired {
            effectiveSession = nil
        } else {
            effectiveSession = session
        }

        switch event {
        case .signedIn, .initialSession, .tokenRefreshed, .userUpdated:
            isSignedIn = effectiveSession != nil
            currentUserID = effectiveSession?.user.id
            currentEmail = effectiveSession?.user.email
            currentUserCreatedAt = effectiveSession?.user.createdAt
        case .signedOut, .userDeleted:
            isSignedIn = false
            currentUserID = nil
            currentEmail = nil
            currentUserCreatedAt = nil
        default:
            break
        }
    }

    /// Step 1 of sign-up: creates the (unconfirmed) account and sends a
    /// 6-digit code to `email`. Name/password rules mirror what the sign-up
    /// screen states — name required, password at least 6 characters.
    func beginSignUp(fullName: String, familyName: String, email: String, password: String) async throws {
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AccountAuthError.nameRequired }
        guard Self.isValidEmail(email) else { throw AccountAuthError.invalidEmail }
        guard password.count >= 6 else { throw AccountAuthError.passwordTooShort }

        var metadata: [String: AnyJSON] = ["full_name": .string(trimmedName)]
        let trimmedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFamily.isEmpty {
            metadata["family_name"] = .string(trimmedFamily)
        }

        do {
            _ = try await client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                data: metadata
            )
        } catch {
            throw AccountAuthError.server(error.localizedDescription)
        }
    }

    /// Step 2: verify the 8-digit confirmation code from the email (the
    /// Supabase project's OTP length is set to 8; the field clamps input to
    /// 8 digits). On success the SDK persists the session to the Keychain
    /// and `authStateChanges` flips `isSignedIn` to true.
    func verifySignUp(email: String, code: String) async throws {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 8 else { throw AccountAuthError.codeIncomplete }
        do {
            _ = try await client.auth.verifyOTP(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                token: trimmedCode,
                type: .signup
            )
        } catch let error as AuthError {
            // Decide from the structured error the server actually returned —
            // never by scanning message text. Verified against the live API:
            // a failed verify comes back as
            //   403 {"error_code":"otp_expired","msg":"Token has expired or is invalid"}
            // and that same code covers a merely mistyped fresh code, so the
            // old `localizedDescription.contains("expired")` guess flagged
            // every failed verification as an expired code.
            Self.logger.error(
                "OTP verification rejected: errorCode=\(error.errorCode.rawValue, privacy: .public) message=\(error.message, privacy: .public)"
            )
            if error.errorCode == .otpExpired {
                throw AccountAuthError.codeExpired
            }
            throw AccountAuthError.server(error.message)
        } catch {
            throw AccountAuthError.server(error.localizedDescription)
        }
    }

    /// Re-sends the sign-up confirmation code (user mistyped it or it expired).
    func resendSignUpCode(email: String) async throws {
        do {
            try await client.auth.resend(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                type: .signup
            )
        } catch {
            throw AccountAuthError.server(error.localizedDescription)
        }
    }

    /// Step 1 of "forgot password": sends an 8-digit recovery code to `email`
    /// (same OTP mechanism as sign-up). Also used to resend the code.
    func beginPasswordReset(email: String) async throws {
        guard Self.isValidEmail(email) else { throw AccountAuthError.invalidEmail }
        do {
            try await client.auth.resetPasswordForEmail(email.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw AccountAuthError.server(error.localizedDescription)
        }
    }

    /// Step 2: verify the recovery code from the email. On success the SDK
    /// establishes a session for the user, so a subsequent `updatePassword`
    /// call can set their new password.
    func verifyPasswordReset(email: String, code: String) async throws {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 8 else { throw AccountAuthError.codeIncomplete }
        do {
            _ = try await client.auth.verifyOTP(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                token: trimmedCode,
                type: .recovery
            )
        } catch let error as AuthError {
            Self.logger.error(
                "Password reset OTP rejected: errorCode=\(error.errorCode.rawValue, privacy: .public) message=\(error.message, privacy: .public)"
            )
            if error.errorCode == .otpExpired {
                throw AccountAuthError.codeExpired
            }
            throw AccountAuthError.server(error.message)
        } catch {
            throw AccountAuthError.server(error.localizedDescription)
        }
    }

    /// Returning-user sign-in (existing, already-verified account).
    func signIn(email: String, password: String) async throws {
        guard Self.isValidEmail(email) else { throw AccountAuthError.invalidEmail }
        do {
            _ = try await client.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch {
            throw AccountAuthError.server(error.localizedDescription)
        }
    }

    /// Changes the signed-in user's password (Account screen). Minimum length
    /// mirrors the sign-up rule.
    func updatePassword(_ newPassword: String) async throws {
        guard newPassword.count >= 6 else { throw AccountAuthError.passwordTooShort }
        do {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
        } catch {
            throw AccountAuthError.server(error.localizedDescription)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw AccountAuthError.server(error.localizedDescription)
        }
    }

    /// Deliberately permissive — real validation is the confirmation email
    /// actually arriving, not a strict regex.
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let domain = trimmed[trimmed.index(after: atIndex)...]
        return trimmed.firstIndex(of: "@") == trimmed.lastIndex(of: "@")
            && atIndex != trimmed.startIndex
            && domain.contains(".")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
    }
}
