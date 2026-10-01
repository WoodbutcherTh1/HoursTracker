import Foundation
import Supabase

enum AccountSyncError: LocalizedError {
    case notSignedIn
    /// Refused an upload that would have overwritten a non-empty cloud
    /// backup with an empty local device — see `uploadBackup`.
    case wouldOverwriteWithEmptyData
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return L10n.accountErrorNotSignedUpYet
        case .wouldOverwriteWithEmptyData: return L10n.accountSyncBlockedEmptyOverwrite
        case .server(let message): return message
        }
    }
}

/// What actually lives inside the `user_backups.payload` JSONB column: just
/// enough to restore a device — settings plus every session. Unlike
/// `FullDataExportDocument` (the user-facing full export), this deliberately
/// leaves out computed breakdowns and the activity log: those are derived
/// from sessions + settings, not source data worth paying storage/bandwidth
/// for on every sync.
struct AccountBackupPayload: Codable {
    let settings: WorkplaceSettings
    let sessions: [WorkSession]
}

/// Uploads/downloads the signed-in user's data to Supabase. Auth identity
/// (`SupabaseAuthManager`) is a separate concern — this type only reads
/// `currentUserID` from it to scope requests; RLS enforces the same scoping
/// server-side regardless.
///
/// Dates inside `payload` are round-tripped through `AnyJSON` rather than
/// relying on the SDK's own default date (en/de)coding strategy for nested
/// Foundation `Date` values, so this always matches the ISO-8601 strategy
/// `PersistenceManager` already uses for local storage — no guessing needed
/// about what the network layer's default happens to be.
@MainActor
final class SupabaseAccountSyncManager {
    static let shared = SupabaseAccountSyncManager()

    private let auth: SupabaseAuthManager

    // `auth` can't default to `.shared` directly: a default parameter
    // expression isn't treated as running on the init's own actor, so
    // referencing another @MainActor type's `.shared` there is rejected
    // under Swift 6 strict concurrency. Resolving it inside the
    // (actor-isolated) init body instead sidesteps that.
    init(auth: SupabaseAuthManager? = nil) {
        self.auth = auth ?? SupabaseAuthManager.shared
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Pushes the current local settings + sessions to this user's backup
    /// row (creating it on first upload, overwriting it on every later
    /// call), and keeps the `profiles` name fields current.
    func uploadBackup(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        fullName: String,
        familyName: String?
    ) async throws {
        guard let userID = auth.currentUserID else { throw AccountSyncError.notSignedIn }
        do {
            // Refuse to let an empty device (e.g. right after a fresh
            // reinstall, before the user has signed back in / restored)
            // silently overwrite a real existing backup via this
            // unconditional upsert — this exact gap once let a user's
            // shifts be permanently erased by an automatic or accidental
            // "Sync Now" tap with nothing on the device yet.
            if sessions.isEmpty, let existing = try? await downloadBackup(), !existing.sessions.isEmpty {
                throw AccountSyncError.wouldOverwriteWithEmptyData
            }

            let payload = AccountBackupPayload(settings: settings, sessions: sessions)
            let payloadData = try Self.makeEncoder().encode(payload)
            let payloadJSON = try JSONDecoder().decode(AnyJSON.self, from: payloadData)

            let backupRow = BackupUpsertRow(
                userId: userID,
                payload: payloadJSON,
                appVersion: FullDataExportManager.appVersionString()
            )
            try await auth.client.from("user_backups").upsert(backupRow).execute()

            let trimmedFamily = familyName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let profileRow = ProfileUpsertRow(
                id: userID,
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                familyName: (trimmedFamily?.isEmpty ?? true) ? nil : trimmedFamily
            )
            try await auth.client.from("profiles").upsert(profileRow).execute()
        } catch let error as AccountSyncError {
            throw error
        } catch {
            throw AccountSyncError.server(error.localizedDescription)
        }
    }

    /// Reads the signed-in user's profile row (display name). `nil` when the
    /// row doesn't exist yet (fresh account, nothing synced) or on any error —
    /// profile display is cosmetic, so it never blocks the account screen.
    nonisolated func fetchProfile() async -> (fullName: String, familyName: String?)? {
        do {
            struct Row: Decodable {
                let fullName: String
                let familyName: String?
                enum CodingKeys: String, CodingKey {
                    case fullName = "full_name"
                    case familyName = "family_name"
                }
            }
            let rows: [Row] = try await auth.client
                .from("profiles")
                .select()
                .eq("id", value: auth.currentUserID as UUID?)
                .execute()
                .value
            guard let row = rows.first else { return nil }
            return (row.fullName, row.familyName)
        } catch {
            return nil
        }
    }

    /// Downloads the signed-in user's backup. `nil` means a brand-new
    /// account that hasn't uploaded anything yet — not an error.
    func downloadBackup() async throws -> AccountBackupPayload? {
        guard auth.currentUserID != nil else { throw AccountSyncError.notSignedIn }
        do {
            let rows: [BackupRow] = try await auth.client
                .from("user_backups")
                .select()
                .execute()
                .value
            guard let jsonValue = rows.first?.payload else { return nil }
            let data = try JSONEncoder().encode(jsonValue)
            return try Self.makeDecoder().decode(AccountBackupPayload.self, from: data)
        } catch let error as AccountSyncError {
            throw error
        } catch {
            throw AccountSyncError.server(error.localizedDescription)
        }
    }
}

/// Row shape for reading `user_backups` — RLS already limits results to the
/// signed-in user's own row, so no `user_id` filter is needed client-side.
private struct BackupRow: Decodable {
    let payload: AnyJSON

    enum CodingKeys: String, CodingKey {
        case payload
    }
}

private struct BackupUpsertRow: Encodable {
    let userId: UUID
    let payload: AnyJSON
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case payload
        case appVersion = "app_version"
    }
}

private struct ProfileUpsertRow: Encodable {
    let id: UUID
    let fullName: String
    let familyName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case familyName = "family_name"
    }
}
