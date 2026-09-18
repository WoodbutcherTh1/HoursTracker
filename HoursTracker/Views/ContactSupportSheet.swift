import SwiftUI
import UIKit

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug
    case feature
    case positive
    case question

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: return L10n.contactSupportCategoryBug
        case .feature: return L10n.contactSupportCategoryFeature
        case .positive: return L10n.contactSupportCategoryPositive
        case .question: return L10n.contactSupportCategoryQuestion
        }
    }

    var icon: String {
        switch self {
        case .bug: return "ladybug.fill"
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
            VStack(spacing: 10) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                Text(L10n.contactSupportSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var nameSection: some View {
        Section {
            TextField(L10n.contactSupportNamePlaceholder, text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    private var categorySection: some View {
        Section(L10n.contactSupportCategoryHeader) {
            ForEach(FeedbackCategory.allCases) { option in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    category = option
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: option.icon)
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.accent)
                            .frame(width: 24)
                        Text(option.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if category == option {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == option ? .isSelected : [])
            }
        }
    }

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
                    .frame(minHeight: 140)
            }
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
        Task {
            let result = await TelegramFeedbackSender.send(text)
            await MainActor.run { handle(result) }
        }
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
