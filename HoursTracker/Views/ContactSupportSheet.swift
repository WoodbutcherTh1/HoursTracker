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

/// Settings sheet: pick a reason, write a message, send it straight to the
/// developer's Telegram chat — styled like the rest of the app (neon card
/// surfaces on the user's chosen background/accent) instead of a plain Form.
struct ContactSupportSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: FeedbackCategory = .bug
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isMessageFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    nameField
                    categoryGrid
                    messageField
                    if !TelegramFeedbackConfig.isConfigured {
                        unavailableNotice
                    }
                    sendButton
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(HomeNeon.coral)
                            .multilineTextAlignment(.center)
                    }
                    Text(L10n.contactSupportDeviceInfoHint)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(20)
            }
            .background(appBackground.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .toolbarBackground(appBackground.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(theme.accent.opacity(0.16))
                .frame(width: 68, height: 68)
                .overlay(
                    Circle().stroke(theme.accent.opacity(0.4), lineWidth: 1.5)
                )
                .overlay(
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(theme.accent)
                )
                .padding(.top, 8)

            Text(L10n.settingsSupport)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(L10n.contactSupportSubtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var nameField: some View {
        TextField(
            "",
            text: $name,
            prompt: Text(L10n.contactSupportNamePlaceholder).foregroundStyle(.white.opacity(0.35))
        )
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .foregroundStyle(.white)
        .tint(theme.accent)
        .padding(14)
        .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(L10n.contactSupportCategoryHeader)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(FeedbackCategory.allCases) { option in
                    categoryChip(option)
                }
            }
        }
    }

    private func categoryChip(_ option: FeedbackCategory) -> some View {
        let isSelected = category == option

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { category = option }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: option.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.82) : theme.accent)
                Text(option.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.82) : .white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? theme.accent : HomeNeon.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(L10n.contactSupportMessageLabel)

            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(L10n.contactSupportMessagePlaceholder)
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .focused($isMessageFocused)
                    .foregroundStyle(.white)
                    .tint(theme.accent)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
            }
            .padding(10)
            .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { isMessageFocused = true }
        }
    }

    private var unavailableNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HomeNeon.coral)
            Text(L10n.contactSupportUnavailable)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HomeNeon.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "paperplane.fill")
                    Text(L10n.contactSupportSend)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.45)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    // MARK: - Actions

    private func send() {
        errorMessage = nil
        isSending = true
        let text = feedbackText()
        Task {
            let result = await TelegramFeedbackSender.send(text)
            await MainActor.run {
                isSending = false
                switch result {
                case .success:
                    viewModel.showSuccessToast(L10n.contactSupportSuccess)
                    dismiss()
                case .notConfigured:
                    errorMessage = L10n.contactSupportUnavailable
                case .failure:
                    errorMessage = L10n.contactSupportError
                }
            }
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
