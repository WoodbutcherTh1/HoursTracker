import Foundation
import os
import UIKit

/// What the owner sees next to each support message: which device and build wrote it.
/// The account (id / email) is deliberately not in here — the server reads it from the
/// signed-in session token, so it can't be spoofed from the request body.
enum SupportSenderContext {
    static func current() -> [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "model": hardwareIdentifier,
            "osVersion": UIDevice.current.systemVersion,
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "locale": Locale.current.identifier
        ]
    }

    /// "iPhone16,1" rather than the generic "iPhone" from `UIDevice.model`.
    static var hardwareIdentifier: String {
        var system = utsname()
        uname(&system)
        let identifier = withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    /// One line for the Telegram feedback message: the account, if signed in.
    @MainActor
    static var accountLine: String {
        let auth = SupabaseAuthManager.shared
        guard auth.isSignedIn, let id = auth.currentUserID else { return "Account: none (not signed in)" }
        return "Account: \(auth.currentEmail ?? "unknown email") (\(id.uuidString))"
    }
}

/// Tracks whether the owner has answered this install's support chat and not yet been
/// read: drives the in-app "reply from support" prompt and the badge on the feedback
/// entry points. The server flags a thread `unread_user` when an admin replies and
/// clears it when the chat is opened (`support-chat` action `list` with `markRead`).
@MainActor
final class SupportInbox: ObservableObject {
    static let shared = SupportInbox()

    @Published private(set) var hasUnreadReply = false
    @Published private(set) var preview: String?
    /// The reply prompt is up (cleared by "Later" or opening the chat).
    @Published private(set) var promptVisible = false
    /// Drives the root-level chat sheet.
    @Published var showChat = false

    private static let logger = Logger(subsystem: "com.hourstracker.app", category: "support")
    private var lastPrompted: String?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Asks the server whether a reply is waiting. Cheap; called on foreground and
    /// when a reply push arrives. A conversation never started returns "no".
    func check() async {
        guard !AnnouncementCenter.isAutomatedRun else { return }
        struct Status: Decodable { let unread: Bool; let preview: String? }
        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/support-chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        let payload = ["action": "status", "deviceId": AnnouncementCenter.stableInstallID()]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let status = try JSONDecoder().decode(Status.self, from: data)
            apply(unread: status.unread, preview: status.preview)
        } catch {
            Self.logger.error("support status failed: \(error.localizedDescription)")
        }
    }

    private func apply(unread: Bool, preview: String?) {
        hasUnreadReply = unread
        self.preview = preview
        guard unread else {
            promptVisible = false
            return
        }
        // Prompt once per distinct reply, not on every foreground.
        let key = preview ?? "reply"
        if lastPrompted != key {
            lastPrompted = key
            promptVisible = true
        }
    }

    /// Opens the chat from the prompt or a tapped reply notification.
    func openChat() {
        promptVisible = false
        showChat = true
    }

    func dismissPrompt() {
        promptVisible = false
    }

    /// The chat was opened and loaded: the server cleared its unread flag.
    func chatOpened() {
        hasUnreadReply = false
        preview = nil
        promptVisible = false
    }
}
