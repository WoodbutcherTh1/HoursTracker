import SwiftUI

/// In-app support chat. Messages go to the admin inbox; a matching auto-reply can answer
/// straight away. Conversations are keyed by this install's id, so there is no sign-in.
struct SupportChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SupportChatModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                if let notice = model.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                inputBar
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(L10n.supportChatTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.editCancel) { dismiss() }
                }
            }
            .task { await model.load() }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if model.messages.isEmpty && !model.isLoading {
                        Text(L10n.supportChatIntro)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 40)
                            .padding(.horizontal, 24)
                    }
                    ForEach(model.messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }
                    if model.isSending {
                        ProgressView()
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(for message: SupportChatModel.Item) -> some View {
        let fromUser = message.sender == "user"
        return HStack {
            if fromUser { Spacer(minLength: 40) }
            VStack(alignment: fromUser ? .trailing : .leading, spacing: 3) {
                if message.sender == "auto" {
                    Text(L10n.supportChatAutoReplyTag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(fromUser ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(fromUser ? Color.accentColor : Color(.secondarySystemBackground))
                    )
            }
            if !fromUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(L10n.supportChatPlaceholder, text: $model.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            Button {
                inputFocused = false
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(model.canSend ? Color.accentColor : Color.gray.opacity(0.4))
            }
            .disabled(!model.canSend)
            .accessibilityLabel(L10n.supportChatSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

@MainActor
final class SupportChatModel: ObservableObject {
    struct Item: Identifiable, Decodable {
        let id: String
        let sender: String
        let body: String
    }

    @Published private(set) var messages: [Item] = []
    @Published var draft: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var notice: String?

    private let session: URLSession
    private var functionURL: URL { SupabaseConfig.projectURL.appendingPathComponent("functions/v1/support-chat") }

    init(session: URLSession = .shared) {
        self.session = session
    }

    var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if await call(["action": "list", "markRead": "true"]) {
            SupportInbox.shared.chatOpened()
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        if await call(["action": "send", "body": text, "language": Self.languageCode], withContext: true) {
            draft = ""
        }
    }

    /// Returns true when the server accepted the request.
    @discardableResult
    private func call(_ extra: [String: String], withContext: Bool = false) async -> Bool {
        var payload: [String: Any] = extra
        payload["deviceId"] = AnnouncementCenter.stableInstallID()
        if extra["markRead"] != nil { payload["markRead"] = true }
        if withContext { payload["context"] = SupportSenderContext.current() }

        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        // Signed in: the server attaches the account to the conversation, so the owner
        // knows who is writing. Anonymous installs chat as before.
        if withContext, let token = try? await SupabaseAuthManager.shared.client.auth.session.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                switch status {
                case 429: notice = L10n.supportChatErrorLimit
                case 503: notice = L10n.supportChatErrorPaused
                default: notice = L10n.supportChatErrorGeneric
                }
                return false
            }
            struct Envelope: Decodable { let messages: [Item] }
            messages = try JSONDecoder().decode(Envelope.self, from: data).messages
            notice = nil
            return true
        } catch {
            notice = L10n.supportChatErrorNetwork
            return false
        }
    }

    private static var languageCode: String {
        switch AppLocale.current {
        case .arabic: return "ar"
        case .hebrew: return "he"
        default: return "en"
        }
    }
}
