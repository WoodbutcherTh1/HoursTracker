import SwiftUI

/// Settings → Admin (visible only to accounts the server lists in `public.admins`).
/// Aggregate stats, and composing/sending announcements in he / ar / en.
struct AdminDashboardView: View {
    @State private var stats: AdminStats?
    @State private var loadingStats = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            statsSection
            Section {
                NavigationLink {
                    AdminComposeView()
                } label: {
                    Label(L10n.adminCompose, systemImage: "square.and.pencil")
                }
                NavigationLink {
                    AdminHistoryView()
                } label: {
                    Label(L10n.adminHistory, systemImage: "clock")
                }
            } header: {
                Text(L10n.adminAnnouncements)
            }
        }
        .navigationTitle(L10n.adminTitle)
        .refreshable { await loadStats() }
        .task { await loadStats() }
        .adminErrorAlert($errorMessage)
    }

    @ViewBuilder
    private var statsSection: some View {
        Section {
            if let stats {
                if let activeNow = stats.activeNow {
                    statRow(L10n.adminStatActiveNow, activeNow)
                }
                if let onShiftNow = stats.onShiftNow {
                    statRow(L10n.adminStatOnShiftNow, onShiftNow)
                }
                statRow(L10n.adminStatDevices, stats.devices)
                statRow(L10n.adminStatActive1d, stats.active1d)
                statRow(L10n.adminStatActive7d, stats.active7d)
                statRow(L10n.adminStatActive30d, stats.active30d)
                statRow(L10n.adminStatAccounts, stats.accounts)
                statRow(L10n.adminStatPush, stats.pushReachable)
                statRow(L10n.adminStatWatch, stats.withWatch)
                statRow(L10n.adminStatWidget, stats.withWidget)
                breakdownRow(L10n.adminStatLanguages, stats.byLanguage)
                breakdownRow(L10n.adminStatVersions, stats.byVersion)
            } else if loadingStats {
                ProgressView()
            }
        } header: {
            Text(L10n.adminStats)
        } footer: {
            Text(L10n.adminStatsFooter)
        }
    }

    private func statRow(_ title: String, _ value: Int) -> some View {
        LabeledContent(title) {
            Text(verbatim: "\(value)").monospacedDigit()
        }
    }

    private func breakdownRow(_ title: String, _ values: [String: Int]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(verbatim: values.sorted { $0.value > $1.value }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadStats() async {
        loadingStats = true
        defer { loadingStats = false }
        do {
            stats = try await AdminAPIClient.shared.stats()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Compose an announcement in the three app languages, pick the audience, check
/// the recipient count, confirm, send.
struct AdminComposeView: View {
    @State private var draft = AnnouncementDraft()
    @State private var language = AppLocale.current.localeIdentifier
    @State private var versionsText = ""
    @State private var emailsText = ""
    @State private var audience: AnnouncementAudience?
    @State private var working = false
    @State private var translating = false
    @State private var confirmSend = false
    @State private var result: AnnouncementSendResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            messageSection
            audienceSection
            Section {
                Toggle(L10n.adminDeliverPush, isOn: $draft.push)
                Toggle(L10n.adminDeliverInApp, isOn: $draft.inApp)
            } header: {
                Text(L10n.adminDelivery)
            }
            Section {
                Button {
                    Task { await countThenConfirm() }
                } label: {
                    HStack {
                        Label(L10n.adminSend, systemImage: "paperplane.fill")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(!draft.isSendable || working)
            } footer: {
                if !draft.missingLanguages.isEmpty {
                    Text(L10n.adminMissingLanguages(draft.missingLanguages.map(Self.languageName).joined(separator: ", ")))
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(L10n.adminCompose)
        .confirmationDialog(
            L10n.adminConfirmTitle(audience?.recipients ?? 0),
            isPresented: $confirmSend,
            titleVisibility: .visible
        ) {
            Button(L10n.adminSend) { Task { await send() } }
            Button(L10n.editCancel, role: .cancel) {}
        } message: {
            Text(L10n.adminConfirmMessage(audience?.pushReachable ?? 0))
        }
        .alert(
            L10n.adminSentTitle,
            isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })
        ) {
            Button(L10n.errorOK, role: .cancel) { result = nil }
        } message: {
            if let result {
                Text(result.pushConfigured
                     ? L10n.adminSentMessage(result.recipients, result.pushSent, result.pushFailed)
                     : L10n.adminSentPushNotConfigured(result.recipients))
            }
        }
        .adminErrorAlert($errorMessage)
    }

    // MARK: Message

    private var messageSection: some View {
        Section {
            Picker(L10n.adminLanguage, selection: $language) {
                ForEach(AnnouncementDraft.languages, id: \.self) { code in
                    Text(verbatim: Self.languageName(code)).tag(code)
                }
            }
            .pickerStyle(.segmented)

            TextField(L10n.adminTitleField, text: binding(\.titles))
                .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
            TextField(L10n.adminBodyField, text: binding(\.bodies), axis: .vertical)
                .lineLimit(4...12)
                .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)

            Button {
                Task { await translate() }
            } label: {
                HStack {
                    Label(L10n.adminTranslate(Self.languageName(language)), systemImage: "character.bubble")
                    if translating { Spacer(); ProgressView() }
                }
            }
            .disabled(!AnnouncementTranslator.isAvailable || translating
                      || (draft.bodies[language] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text(L10n.adminMessage)
        } footer: {
            Text(AnnouncementTranslator.isAvailable ? L10n.adminTranslateHint : L10n.adminTranslateNeedsKey)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AnnouncementDraft, [String: String]>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath][language] ?? "" },
            set: { draft[keyPath: keyPath][language] = $0 }
        )
    }

    // MARK: Audience

    private var audienceSection: some View {
        Section {
            Picker(L10n.adminAudience, selection: $draft.target.kind) {
                Text(L10n.adminAudienceAll).tag(AnnouncementTarget.Kind.all)
                Text(L10n.adminAudienceLanguage).tag(AnnouncementTarget.Kind.language)
                Text(L10n.adminAudienceVersion).tag(AnnouncementTarget.Kind.version)
                Text(L10n.adminAudienceUsers).tag(AnnouncementTarget.Kind.users)
            }
            switch draft.target.kind {
            case .all:
                EmptyView()
            case .language:
                ForEach(AnnouncementDraft.languages, id: \.self) { code in
                    Toggle(isOn: languageBinding(code)) { Text(verbatim: Self.languageName(code)) }
                }
            case .version:
                TextField(L10n.adminVersionsField, text: $versionsText)
                    .keyboardType(.numbersAndPunctuation)
            case .users:
                TextField(L10n.adminEmailsField, text: $emailsText, axis: .vertical)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...8)
            }
            if let audience {
                Text(L10n.adminAudienceCount(audience.recipients, audience.pushReachable))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !audience.unmatchedEmails.isEmpty {
                    Text(L10n.adminUnmatchedEmails(audience.unmatchedEmails.joined(separator: ", ")))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text(L10n.adminAudience)
        }
        .onChange(of: draft.target.kind) { _, _ in audience = nil }
    }

    private func languageBinding(_ code: String) -> Binding<Bool> {
        Binding(
            get: { draft.target.languages?.contains(code) ?? false },
            set: { isOn in
                var chosen = Set(draft.target.languages ?? [])
                if isOn { chosen.insert(code) } else { chosen.remove(code) }
                draft.target.languages = AnnouncementDraft.languages.filter(chosen.contains)
                audience = nil
            }
        )
    }

    /// The target as it will be sent, with the free-text fields parsed.
    private var resolvedTarget: AnnouncementTarget {
        var target = AnnouncementTarget(kind: draft.target.kind)
        switch target.kind {
        case .all: break
        case .language: target.languages = draft.target.languages ?? []
        case .version: target.versions = Self.split(versionsText)
        case .users: target.emails = Self.split(emailsText).map { $0.lowercased() }
        }
        return target
    }

    static func split(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",; \n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Actions

    private func countThenConfirm() async {
        working = true
        defer { working = false }
        do {
            let target = resolvedTarget
            draft.target = target
            let counted = try await AdminAPIClient.shared.audience(for: target)
            audience = counted
            if counted.recipients > 0 {
                confirmSend = true
            } else {
                errorMessage = L10n.adminNoRecipients
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        working = true
        defer { working = false }
        do {
            result = try await AdminAPIClient.shared.send(draft)
            let kept = draft.target
            draft = AnnouncementDraft()
            draft.target = kept
            audience = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func translate() async {
        translating = true
        defer { translating = false }
        do {
            let translations = try await AnnouncementTranslator.translate(
                title: draft.titles[language] ?? "",
                body: draft.bodies[language] ?? "",
                from: language
            )
            for (code, translation) in translations {
                draft.titles[code] = translation.title
                draft.bodies[code] = translation.body
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func languageName(_ code: String) -> String {
        switch code {
        case "he": return "עברית"
        case "ar": return "العربية"
        default: return "English"
        }
    }
}

/// The latest announcements with delivery and "seen" counts.
struct AdminHistoryView: View {
    @State private var items: [AdminAnnouncementRecord] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if items.isEmpty && !loading {
                Text(L10n.adminHistoryEmpty).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: Self.pick(item.title))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: Self.pick(item.body))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text(L10n.adminHistoryCounts(item.recipients, item.pushSent, item.seen))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let date = item.createdAt {
                        Text(date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .overlay { if loading && items.isEmpty { ProgressView() } }
        .navigationTitle(L10n.adminHistory)
        .refreshable { await load() }
        .task { await load() }
        .adminErrorAlert($errorMessage)
    }

    /// The copy in the admin's own app language, else English, else any.
    static func pick(_ texts: [String: String]) -> String {
        texts[AppLocale.current.localeIdentifier] ?? texts["en"] ?? texts.values.first ?? ""
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await AdminAPIClient.shared.history()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func adminErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            L10n.errorTitle,
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })
        ) {
            Button(L10n.errorOK, role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
