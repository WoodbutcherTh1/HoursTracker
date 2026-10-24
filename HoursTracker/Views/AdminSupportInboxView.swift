import SwiftUI

/// Admin side of the support chat: the conversations, and a reply box per conversation.
/// Talks to `supabase/functions/support-admin`, which checks the admin list on every call.
struct AdminSupportInboxView: View {
    @StateObject private var model = AdminSupportModel()

    var body: some View {
        List {
            if let notice = model.notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                if model.threads.isEmpty && !model.isLoading {
                    Text(L10n.adminSupportEmpty)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.threads) { thread in
                    NavigationLink {
                        AdminSupportThreadView(model: model, thread: thread)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(thread.unreadAdmin ? Color.accentColor : Color.clear)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(thread.senderTitle)
                                    .font(.body.weight(thread.unreadAdmin ? .semibold : .regular))
                                Text(thread.statusLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(thread.lastMessageAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L10n.adminSupportTitle)
            }
        }
        .navigationTitle(L10n.adminSupportTitle)
        .refreshable { await model.loadThreads() }
        .task { await model.loadThreads() }
    }
}

struct AdminSupportThreadView: View {
    @ObservedObject var model: AdminSupportModel
    let thread: AdminSupportModel.Thread
    @State private var reply = ""
    @State private var messages: [AdminSupportModel.Message] = []
    @State private var isBusy = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    senderCard
                    ForEach(messages) { message in
                        bubble(message)
                    }
                }
                .padding(14)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(L10n.supportChatPlaceholder, text: $reply, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
                Button {
                    focused = false
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 22))
                }
                .disabled(isBusy || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(L10n.supportChatSend)
            }
            .padding(12)
            .background(.bar)
        }
        .navigationTitle(L10n.adminSupportConversation(thread.deviceRef))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            messages = await model.loadMessages(threadId: thread.id)
            await model.markRead(threadId: thread.id)
        }
    }

    /// Who is on the other end: account (or none), device, OS, app build, locale.
    private var senderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            senderRow(L10n.adminSupportAccount, thread.userEmail ?? L10n.adminSupportNoAccount)
            if let userId = thread.userId { senderRow(L10n.adminSupportUserId, userId) }
            senderRow(L10n.adminSupportDevice, [thread.deviceModel, thread.osVersion.map { "iOS \($0)" }]
                .compactMap { $0 }.joined(separator: " · "))
            senderRow(L10n.adminSupportApp, thread.appVersion.map { "v\($0)" + (thread.build.map { " (\($0))" } ?? "") } ?? "")
            senderRow(L10n.adminSupportLocale, thread.locale ?? "")
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemBackground)))
    }

    @ViewBuilder
    private func senderRow(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
        }
    }

    private func bubble(_ message: AdminSupportModel.Message) -> some View {
        let fromUser = message.sender == "user"
        return HStack {
            if !fromUser { Spacer(minLength: 40) }
            VStack(alignment: fromUser ? .leading : .trailing, spacing: 3) {
                Text(message.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(message.sender == "admin" ? Color.white : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(message.sender == "admin" ? Color.accentColor : Color(.secondarySystemBackground))
                    )
                if fromUser, let context = message.context {
                    Text(context.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if fromUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity)
    }

    private func send() async {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        if let updated = await model.reply(threadId: thread.id, body: text) {
            messages = updated
            reply = ""
        }
    }
}

@MainActor
final class AdminSupportModel: ObservableObject {
    struct Thread: Identifiable, Decodable {
        let id: String
        let status: String
        let unreadAdmin: Bool
        let lastMessageAt: Date
        let deviceRef: String
        /// Who the conversation is with. Optional so an older server still decodes.
        let userId: String?
        let userEmail: String?
        let deviceModel: String?
        let osVersion: String?
        let appVersion: String?
        let build: String?
        let locale: String?

        enum CodingKeys: String, CodingKey {
            case id, status, build, locale
            case unreadAdmin = "unread_admin"
            case lastMessageAt = "last_message_at"
            case deviceRef = "device_ref"
            case userId = "user_id"
            case userEmail = "user_email"
            case deviceModel = "device_model"
            case osVersion = "os_version"
            case appVersion = "app_version"
        }

        /// Email when signed in, otherwise the short device reference.
        var senderTitle: String {
            userEmail ?? (userId != nil ? L10n.adminSupportAccount : L10n.adminSupportConversation(deviceRef))
        }

        var statusLabel: String {
            switch status {
            case "answered": return L10n.adminSupportAnswered
            case "closed": return L10n.adminSupportClosed
            default: return L10n.adminSupportOpen
            }
        }
    }

    /// What the app reported when the user wrote this message, plus the account the
    /// server verified from their session.
    struct SenderContext: Decodable, Equatable {
        let userId: String?
        let email: String?
        let model: String?
        let osVersion: String?
        let appVersion: String?
        let build: String?
        let locale: String?

        var summary: String {
            let device = [model, osVersion.map { "iOS \($0)" }].compactMap { $0 }.joined(separator: " · ")
            let app = appVersion.map { "v\($0)" + (build.map { " (\($0))" } ?? "") }
            return [email ?? L10n.adminSupportNoAccount, device.isEmpty ? nil : device, app, locale]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    struct Message: Identifiable, Decodable {
        let id: String
        let sender: String
        let body: String
        let context: SenderContext?
    }

    @Published private(set) var threads: [Thread] = []
    @Published private(set) var isLoading = false
    @Published private(set) var notice: String?

    private let session: URLSession
    private static let functionURL = SupabaseConfig.projectURL.appendingPathComponent("functions/v1/support-admin")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadThreads() async {
        isLoading = true
        defer { isLoading = false }
        struct Envelope: Decodable { let threads: [Thread] }
        if let envelope: Envelope = await call(["action": "threads"]) {
            threads = envelope.threads
        }
    }

    func loadMessages(threadId: String) async -> [Message] {
        struct Envelope: Decodable { let messages: [Message] }
        let envelope: Envelope? = await call(["action": "messages", "threadId": threadId])
        return envelope?.messages ?? []
    }

    func reply(threadId: String, body: String) async -> [Message]? {
        struct Envelope: Decodable { let messages: [Message] }
        let envelope: Envelope? = await call(["action": "reply", "threadId": threadId, "body": body])
        await loadThreads()
        return envelope?.messages
    }

    func markRead(threadId: String) async {
        struct Ok: Decodable { let ok: Bool }
        let _: Ok? = await call(["action": "mark_read", "threadId": threadId])
        await loadThreads()
    }

    func call<Response: Decodable>(_ body: [String: Any]) async -> Response? {
        guard let token = try? await SupabaseAuthManager.shared.client.auth.session.accessToken else {
            notice = L10n.adminSupportNotSignedIn
            return nil
        }
        var request = URLRequest(url: Self.functionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                notice = L10n.adminSupportFailed
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let raw = try container.decode(String.self)
                let withFraction = ISO8601DateFormatter()
                withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = withFraction.date(from: raw) { return date }
                return ISO8601DateFormatter().date(from: raw) ?? Date()
            }
            notice = nil
            return try decoder.decode(Response.self, from: data)
        } catch {
            notice = L10n.adminSupportFailed
            return nil
        }
    }
}
