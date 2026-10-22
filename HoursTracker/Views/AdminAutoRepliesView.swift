import SwiftUI

/// Admin → Support → Automatic replies. A rule answers a user's message right away when
/// it contains one of its keywords; the reply is picked in the user's language.
struct AdminAutoRepliesView: View {
    @StateObject private var model = AdminSupportModel()
    @State private var rules: [AdminSupportModel.AutoReply] = []
    @State private var editing: AdminSupportModel.AutoReply?
    @State private var isLoading = false

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
                if rules.isEmpty && !isLoading {
                    Text(L10n.adminAutoRepliesEmpty)
                        .foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    Button {
                        editing = rule
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.keywords.joined(separator: ", "))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(rule.enabled ? Color.primary : Color.secondary)
                            Text(rule.previewText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.compactMap { rules[$0].id }
                    Task {
                        for id in ids { await model.deleteAutoReply(id: id) }
                        await reload()
                    }
                }
            } footer: {
                Text(L10n.adminAutoRepliesHint)
            }
        }
        .navigationTitle(L10n.adminAutoRepliesTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = AdminSupportModel.AutoReply()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.adminAutoRepliesAdd)
            }
        }
        .sheet(item: $editing) { rule in
            AdminAutoReplyEditor(rule: rule) { saved in
                Task {
                    if await model.saveAutoReply(saved) {
                        editing = nil
                        await reload()
                    }
                }
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        rules = await model.loadAutoReplies()
    }
}

private struct AdminAutoReplyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: AdminSupportModel.AutoReply
    @State private var keywordsText: String = ""
    let onSave: (AdminSupportModel.AutoReply) -> Void

    init(rule: AdminSupportModel.AutoReply, onSave: @escaping (AdminSupportModel.AutoReply) -> Void) {
        _rule = State(initialValue: rule)
        _keywordsText = State(initialValue: rule.keywords.joined(separator: ", "))
        self.onSave = onSave
    }

    private var parsedKeywords: [String] {
        keywordsText
            .split(whereSeparator: { $0 == "," || $0 == "،" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.adminAutoRepliesKeywordsPlaceholder, text: $keywordsText, axis: .vertical)
                        .lineLimit(1...3)
                    Toggle(L10n.adminAutoRepliesEnabled, isOn: $rule.enabled)
                } header: {
                    Text(L10n.adminAutoRepliesKeywords)
                } footer: {
                    Text(L10n.adminAutoRepliesKeywordsHint)
                }
                Section("עברית") {
                    TextField("", text: $rule.replyHe, axis: .vertical).lineLimit(2...6)
                }
                Section("العربية") {
                    TextField("", text: $rule.replyAr, axis: .vertical).lineLimit(2...6)
                }
                Section("English") {
                    TextField("", text: $rule.replyEn, axis: .vertical).lineLimit(2...6)
                }
            }
            .navigationTitle(L10n.adminAutoRepliesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.editCancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.supportChatSend) {
                        var saved = rule
                        saved.keywords = parsedKeywords
                        onSave(saved)
                    }
                    .disabled(parsedKeywords.isEmpty || !rule.hasAnyReply)
                }
            }
        }
    }
}

extension AdminSupportModel {
    struct AutoReply: Identifiable, Decodable {
        var id: String?
        var keywords: [String] = []
        var replyEn: String = ""
        var replyHe: String = ""
        var replyAr: String = ""
        var enabled: Bool = true

        /// Stable identity for SwiftUI, including a new rule that has no server id yet.
        var localID = UUID()

        enum CodingKeys: String, CodingKey {
            case id, keywords, enabled
            case replyEn = "reply_en"
            case replyHe = "reply_he"
            case replyAr = "reply_ar"
        }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
            replyEn = try c.decodeIfPresent(String.self, forKey: .replyEn) ?? ""
            replyHe = try c.decodeIfPresent(String.self, forKey: .replyHe) ?? ""
            replyAr = try c.decodeIfPresent(String.self, forKey: .replyAr) ?? ""
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }

        var hasAnyReply: Bool {
            ![replyEn, replyHe, replyAr].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        var previewText: String {
            [replyHe, replyAr, replyEn].first { !$0.isEmpty } ?? ""
        }
    }

    func loadAutoReplies() async -> [AutoReply] {
        struct Envelope: Decodable { let rules: [AutoReply] }
        let envelope: Envelope? = await call(["action": "auto_replies"])
        return envelope?.rules ?? []
    }

    func saveAutoReply(_ rule: AutoReply) async -> Bool {
        struct Ok: Decodable { let ok: Bool }
        var payload: [String: Any] = [
            "keywords": rule.keywords,
            "reply_en": rule.replyEn,
            "reply_he": rule.replyHe,
            "reply_ar": rule.replyAr,
            "enabled": rule.enabled
        ]
        if let id = rule.id { payload["id"] = id }
        let result: Ok? = await call(["action": "auto_reply_save", "rule": payload])
        return result?.ok == true
    }

    func deleteAutoReply(id: String) async {
        struct Ok: Decodable { let ok: Bool }
        let _: Ok? = await call(["action": "auto_reply_delete", "id": id])
    }
}

extension AdminSupportModel.AutoReply: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.localID == rhs.localID }
    func hash(into hasher: inout Hasher) { hasher.combine(localID) }
}
