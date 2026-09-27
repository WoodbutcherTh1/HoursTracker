import Foundation

/// Aggregate numbers for the owner dashboard. Counts only — the server never
/// returns anyone's shifts, pay or identity (see `admin_stats()` in the migration).
struct AdminStats: Decodable, Equatable {
    let devices: Int
    let active1d: Int
    let active7d: Int
    let active30d: Int
    let accounts: Int
    let pushReachable: Int
    let withWatch: Int
    let withWidget: Int
    let byLanguage: [String: Int]
    let byVersion: [String: Int]
}

/// Who an announcement goes to.
struct AnnouncementTarget: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case all, language, version, users
        var id: String { rawValue }
    }

    var kind: Kind
    var languages: [String]?
    var versions: [String]?
    var emails: [String]?

    static let everyone = AnnouncementTarget(kind: .all)
}

struct AnnouncementAudience: Decodable, Equatable {
    let recipients: Int
    let pushReachable: Int
    let unmatchedEmails: [String]
}

struct AnnouncementSendResult: Decodable, Equatable {
    let recipients: Int
    let pushSent: Int
    let pushFailed: Int
    let pushConfigured: Bool
}

/// The three language versions of an announcement. Empty languages fall back to
/// English on the server.
struct AnnouncementDraft: Equatable {
    static let languages = ["he", "ar", "en"]

    var titles: [String: String] = [:]
    var bodies: [String: String] = [:]
    var target: AnnouncementTarget = .everyone
    var push = true
    var inApp = true

    func trimmed(_ texts: [String: String]) -> [String: String] {
        texts.compactMapValues { value in
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    /// Something to say in at least one language, and a way to deliver it.
    var isSendable: Bool {
        !trimmed(bodies).isEmpty && (push || inApp)
    }

    /// Languages with no body yet — shown as a warning so the owner doesn't send
    /// an Arabic user the English copy by accident.
    var missingLanguages: [String] {
        let bodies = trimmed(bodies)
        guard !bodies.isEmpty else { return [] }
        return Self.languages.filter { bodies[$0] == nil }
    }
}

struct AdminAnnouncementRecord: Decodable, Identifiable, Equatable {
    let id: UUID
    let title: [String: String]
    let body: [String: String]
    let target: AnnouncementTarget
    let push: Bool
    let inApp: Bool
    let recipients: Int
    let pushSent: Int
    let pushFailed: Int
    let seen: Int
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, body, target, push, recipients, seen
        case inApp = "in_app"
        case pushSent = "push_sent"
        case pushFailed = "push_failed"
        case createdAt = "created_at"
    }
}

enum AdminAPIError: LocalizedError, Equatable {
    case notSignedIn
    case forbidden
    case rateLimited
    case server(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return L10n.adminErrorNotSignedIn
        case .forbidden: return L10n.adminErrorForbidden
        case .rateLimited: return L10n.adminErrorRateLimited
        case .server(let status): return L10n.adminErrorServer(status)
        case .network(let message): return message
        }
    }
}

/// Client for `supabase/functions/admin-api`. The server checks the signed-in
/// account against `public.admins` on every call; `isAdmin` here only decides
/// whether Settings shows the (otherwise useless) Admin entry.
@MainActor
final class AdminAPIClient: ObservableObject {
    static let shared = AdminAPIClient()

    @Published private(set) var isAdmin = false
    private var checkedUserID: UUID?

    private static let functionURL = SupabaseConfig.projectURL.appendingPathComponent("functions/v1/admin-api")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Asks the server once per signed-in account whether it is an admin.
    func checkAccess() async {
        let auth = SupabaseAuthManager.shared
        guard auth.isSignedIn, let userID = auth.currentUserID else {
            isAdmin = false
            checkedUserID = nil
            return
        }
        guard userID != checkedUserID, !AnnouncementCenter.isAutomatedRun else { return }
        struct WhoAmI: Decodable { let isAdmin: Bool }
        if let result: WhoAmI = try? await call(["action": "whoami"]) {
            isAdmin = result.isAdmin
            checkedUserID = userID
        }
    }

    func stats() async throws -> AdminStats {
        try await call(["action": "stats"])
    }

    func audience(for target: AnnouncementTarget) async throws -> AnnouncementAudience {
        try await call(Request(action: "audience", target: target))
    }

    func send(_ draft: AnnouncementDraft) async throws -> AnnouncementSendResult {
        try await call(Request(
            action: "send",
            title: draft.trimmed(draft.titles),
            body: draft.trimmed(draft.bodies),
            target: draft.target,
            push: draft.push,
            inApp: draft.inApp
        ))
    }

    func history() async throws -> [AdminAnnouncementRecord] {
        struct History: Decodable { let announcements: [AdminAnnouncementRecord] }
        let result: History = try await call(["action": "history"])
        return result.announcements
    }

    private struct Request: Encodable {
        let action: String
        var title: [String: String]?
        var body: [String: String]?
        var target: AnnouncementTarget?
        var push: Bool?
        var inApp: Bool?
    }

    private func call<Body: Encodable, Response: Decodable>(_ body: Body) async throws -> Response {
        guard let token = try? await SupabaseAuthManager.shared.client.auth.session.accessToken else {
            throw AdminAPIError.notSignedIn
        }
        var request = URLRequest(url: Self.functionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AdminAPIError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200..<300: break
        case 401: throw AdminAPIError.notSignedIn
        case 403: throw AdminAPIError.forbidden
        case 429: throw AdminAPIError.rateLimited
        default: throw AdminAPIError.server(status)
        }
        return try AnnouncementCenter.decoder.decode(Response.self, from: data)
    }
}

/// "Auto-translate" for the compose screen: fills the other two languages from
/// the one the owner wrote, using the owner's own Gemini key from the Keychain
/// (same as the assistant and scanners — the app ships no key). The owner
/// reviews and edits the result before sending.
enum AnnouncementTranslator {
    struct Translation: Decodable, Equatable {
        let title: String
        let body: String
    }

    static var isAvailable: Bool {
        !(KeychainStore.string(for: .geminiAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func translate(
        title: String,
        body: String,
        from source: String,
        session: URLSession = .shared
    ) async throws -> [String: Translation] {
        guard let apiKey = KeychainStore.string(for: .geminiAPIKey), !apiKey.isEmpty,
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        else { throw ScannerLLMError.missingAPIKey }

        let targets = AnnouncementDraft.languages.filter { $0 != source }
        let instructions = """
        You translate short in-app announcements for HoursTracker, an Israeli work-hours app. \
        Translate from \(source) into \(targets.joined(separator: " and ")). \
        Hebrew must be natural Israeli Hebrew; Arabic must be clear everyday Arabic as spoken by \
        Arab citizens of Israel. Keep the tone, emoji, line breaks and any app terms. \
        Reply with JSON only: {"<language code>": {"title": "...", "body": "..."}} for each target.
        """
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "system_instruction": ["parts": [["text": instructions]]],
            "contents": [["role": "user", "parts": [["text": "Title: \(title)\n\nBody:\n\(body)"]]]],
            "generationConfig": ["temperature": 0.2, "responseMimeType": "application/json"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ScannerLLMError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let json = text.data(using: .utf8)
        else { throw ScannerLLMError.invalidResponse("missing candidates") }
        let decoded = try JSONDecoder().decode([String: Translation].self, from: json)
        return decoded.filter { targets.contains($0.key) }
    }
}
