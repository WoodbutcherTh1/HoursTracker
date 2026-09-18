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
}

/// Settings sheet: pick a reason, write a message, send it straight to the
/// developer's Telegram chat — no email client hop required.
struct ContactSupportSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: FeedbackCategory = .bug
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            Form {
                if !TelegramFeedbackConfig.isConfigured {
                    Section {
                        Text(L10n.contactSupportUnavailable)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField(L10n.contactSupportNamePlaceholder, text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section(L10n.contactSupportCategoryHeader) {
                    Picker(L10n.contactSupportCategoryHeader, selection: $category) {
                        ForEach(FeedbackCategory.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 140)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.settingsSupport)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.editCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        send()
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text(L10n.contactSupportSend)
                        }
                    }
                    .disabled(!canSend)
                }
            }
        }
    }

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
