import SwiftUI
import UIKit

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug
    case crash
    case payCalculation
    case translation
    case feature
    case positive
    case question

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: return L10n.contactSupportCategoryBug
        case .crash: return L10n.contactSupportCategoryCrash
        case .payCalculation: return L10n.contactSupportCategoryPayCalculation
        case .translation: return L10n.contactSupportCategoryTranslation
        case .feature: return L10n.contactSupportCategoryFeature
        case .positive: return L10n.contactSupportCategoryPositive
        case .question: return L10n.contactSupportCategoryQuestion
        }
    }

    var icon: String {
        switch self {
        case .bug: return "ladybug.fill"
        case .crash: return "exclamationmark.octagon.fill"
        case .payCalculation: return "banknote.fill"
        case .translation: return "globe"
        case .feature: return "sparkles"
        case .positive: return "heart.fill"
        case .question: return "questionmark.circle.fill"
        }
    }
}

private enum SendState: Equatable {
    case idle
    case sending
    case success
}

/// Settings sheet: pick a reason, write a message, send it straight to the
/// developer's Telegram chat. Composed the way Apple's own compose sheets are
/// (Mail, Reminders, Notes): a titled nav bar with Cancel/Send, a grouped
/// `Form`, and a checkmark-style row list for the one exclusive choice —
/// rather than bespoke chrome, so it inherits standard Dynamic Type, dark
/// mode, and VoiceOver behavior for free. The app's own accent color still
/// comes through via tint, matching how `SettingsView` itself blends a
/// native `Form` with the custom background.
struct ContactSupportSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: FeedbackCategory = .bug
    @State private var message = ""
    @State private var attachLog = false
    @State private var sendState: SendState = .idle
    @State private var errorMessage: String?

    private var isMessageValid: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                heroSection
                nameSection
                categorySection
                messageSection
            }
            .scrollContentBackground(.hidden)
            .background(appBackground.background.ignoresSafeArea())
            .tint(theme.accent)
            .navigationTitle(L10n.settingsSupport)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.editCancel) { dismiss() }
                        .disabled(sendState != .idle)
                }
                ToolbarItem(placement: .confirmationAction) {
                    sendBarButton
                }
            }
            .toolbarBackground(appBackground.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [theme.accent, theme.accent.darkened(by: 0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: theme.accent.opacity(0.35), radius: 14, y: 6)

                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(L10n.contactSupportSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .listRowBackground(Color.clear)
        }
    }

    private var nameSection: some View {
        Section {
            TextField(L10n.contactSupportNamePlaceholder, text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.vertical, 3)
                .listRowBackground(HomeNeon.card)
        }
    }

    private var categorySection: some View {
        Section {
            Picker(selection: $category) {
                ForEach(FeedbackCategory.allCases) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(theme.accent.opacity(0.18))
                            .frame(width: 28, height: 28)
                        Image(systemName: category.icon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                    Text(L10n.contactSupportCategoryHeader)
                }
            }
            .pickerStyle(.menu)
            .padding(.vertical, 3)
            .listRowBackground(HomeNeon.card)
            .onChange(of: category) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(L10n.contactSupportMessagePlaceholder)
                        .foregroundStyle(Color(uiColor: .placeholderText))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
            }
            .listRowBackground(HomeNeon.card)
        } header: {
            Text(L10n.contactSupportMessageLabel)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if !TelegramFeedbackConfig.isConfigured {
                    Label(L10n.contactSupportUnavailable, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Text(L10n.contactSupportDeviceInfoHint)
                    .font(.footnote)
            }
        }

        Section {
            Toggle(isOn: $attachLog) {
                Label(L10n.contactSupportAttachLog, systemImage: "doc.text")
            }
            .listRowBackground(HomeNeon.card)
        } footer: {
            Text(L10n.contactSupportAttachLogHint)
                .font(.footnote)
        }
    }

    private var sendBarButton: some View {
        Button {
            send()
        } label: {
            switch sendState {
            case .idle:
                Text(L10n.contactSupportSend).fontWeight(.semibold)
            case .sending:
                ProgressView()
            case .success:
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
            }
        }
        .disabled(sendState != .idle || !isMessageValid)
        .animation(.default, value: sendState)
    }

    // MARK: - Actions

    private func send() {
        errorMessage = nil
        sendState = .sending
        let text = feedbackText()
        let shouldAttachLog = attachLog
        Task {
            let result = await TelegramFeedbackSender.send(text)
            if result == .success, shouldAttachLog {
                await attachActivityLog()
            }
            await MainActor.run { handle(result) }
        }
    }

    /// Best-effort follow-up upload: the main feedback message already went
    /// through by the time this runs, so a failure here never blocks the user
    /// or surfaces its own error — it just means the log didn't make it.
    private func attachActivityLog() async {
        guard let logURL = try? await MainActor.run(body: { try ActivityLogStore.shared.export(format: .txt) })
        else { return }
        _ = await TelegramFeedbackSender.sendDocument(fileURL: logURL, caption: "HoursTracker activity log")
    }

    private func handle(_ result: TelegramFeedbackSendResult) {
        switch result {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            sendState = .success
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                await MainActor.run {
                    viewModel.showSuccessToast(L10n.contactSupportSuccess)
                    dismiss()
                }
            }
        case .notConfigured:
            sendState = .idle
            errorMessage = L10n.contactSupportUnavailable
        case .failure:
            sendState = .idle
            errorMessage = L10n.contactSupportError
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// Device/app details ride along automatically so the user never has to
    /// type them — name stays optional since it's the one field they might
    /// not want to share.
    private func feedbackText() -> String {
        let device = UIDevice.current
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = ["HoursTracker feedback", "Category: \(category.title)"]
        if !trimmedName.isEmpty {
            lines.append("From: \(trimmedName)")
        }
        lines.append("")
        lines.append(message.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("")
        lines.append("— \(device.model), iOS \(device.systemVersion), app \(appVersion) (\(build))")
        return lines.joined(separator: "\n")
    }
}
