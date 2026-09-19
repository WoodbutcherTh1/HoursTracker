import Foundation
import Supabase

/// Errors surfaced to the sign-up / sign-in screens, already carrying a
/// localized message so the UI never has to interpret a raw SDK error.
enum AccountAuthError: LocalizedError {
    case nameRequired
    case invalidEmail
    case passwordTooShort
    case codeIncomplete
    case notSignedUpYet
    case server(String)

    var errorDescription: String? {
        switch self {
        case .nameRequired: return L10n.accountErrorNameRequired
        case .invalidEmail: return L10n.accountErrorInvalidEmail
        case .passwordTooShort: return L10n.accountErrorPasswordTooShort
        case .codeIncomplete: return L10n.accountErrorCodeIncomplete
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

    let client: SupabaseClient

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var currentUserID: UUID?
    @Published private(set) var currentEmail: String?

    private var authStateTask: Task<Void, Never>?

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.publishableKey
        )
        let session = client.auth.currentSession
        isSignedIn = session != nil
        currentUserID = session?.user.id
        currentEmail = session?.user.email

        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                await self.handle(event: event, session: session)
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    private func handle(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .signedIn, .initialSession, .tokenRefreshed, .userUpdated:
            isSignedIn = session != nil
            currentUserID = session?.user.id
            currentEmail = session?.user.email
        case .signedOut, .userDeleted:
            isSignedIn = false
            currentUserID = nil
            currentEmail = nil
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

        var metadata: [String: JSONValue] = ["full_name": .string(trimmedName)]
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

    /// Step 2: verify the 6-digit code from the confirmation email. On
    /// success the SDK persists the session to the Keychain and
    /// `authStateChanges` flips `isSignedIn` to true.
    func verifySignUp(email: String, code: String) async throws {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 6 else { throw AccountAuthError.codeIncomplete }
        do {
            _ = try await client.auth.verifyOTP(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                token: trimmedCode,
                type: .signup
            )
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
