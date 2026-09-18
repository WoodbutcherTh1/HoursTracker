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

/// A few pixels of horizontal jitter that decays to zero — the classic
/// "that didn't work" shake, driven by an ever-increasing `animatableData`
/// so repeat failures always restart it from the top.
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 7
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0
        ))
    }
}

/// Settings sheet: pick a reason, write a message, send it straight to the
/// developer's Telegram chat. Styled like the rest of the app — neon card
/// surfaces on the user's chosen background/accent, a soft glow behind the
/// header, focus-reactive fields, and a send button that morphs into a
/// checkmark on success — instead of a plain system Form.
struct ContactSupportSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field: Hashable {
        case name
        case message
    }

    @State private var name = ""
    @State private var category: FeedbackCategory = .bug
    @State private var message = ""
    @State private var sendState: SendState = .idle
    @State private var errorMessage: String?
    @State private var shakeTicks: CGFloat = 0
    @State private var appeared = false
    @State private var pulse = false
    @FocusState private var focusedField: Field?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var isMessageValid: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                        .reveal(appeared, delay: 0)
                    nameField
                        .reveal(appeared, delay: 0.05)
                    categoryGrid
                        .reveal(appeared, delay: 0.1)
                    messageField
                        .reveal(appeared, delay: 0.15)
                    if !TelegramFeedbackConfig.isConfigured {
                        unavailableNotice
                            .reveal(appeared, delay: 0.18)
                    }
                    sendButton
                        .reveal(appeared, delay: 0.2)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(HomeNeon.coral)
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Text(L10n.contactSupportDeviceInfoHint)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .reveal(appeared, delay: 0.24)
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
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                }
            }
            .toolbarBackground(appBackground.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.22))
                    .frame(width: 150, height: 150)
                    .blur(radius: 34)
                    .opacity(pulse ? 0.85 : 0.45)

                Circle()
                    .fill(theme.accent.opacity(0.16))
                    .frame(width: 68, height: 68)
                    .overlay(Circle().stroke(theme.accent.opacity(0.4), lineWidth: 1.5))
                    .overlay(
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    )
                    .shadow(color: theme.accent.opacity(0.5), radius: pulse ? 18 : 8)
                    .scaleEffect(pulse ? 1.05 : 1.0)
            }
            .padding(.top, 8)
            .padding(.bottom, 2)

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
        .focused($focusedField, equals: .name)
        .padding(14)
        .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fieldGlow(isActive: focusedField == .name, accent: theme.accent)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { category = option }
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
            .shadow(color: isSelected ? theme.accent.opacity(0.45) : .clear, radius: 12, y: 4)
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel(L10n.contactSupportMessageLabel)
                Spacer()
                if !message.isEmpty {
                    Text("\(message.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }

            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(L10n.contactSupportMessagePlaceholder)
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .focused($focusedField, equals: .message)
                    .foregroundStyle(.white)
                    .tint(theme.accent)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
            }
            .padding(10)
            .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .fieldGlow(isActive: focusedField == .message, accent: theme.accent)
            .onTapGesture { focusedField = .message }
            .animation(.easeInOut(duration: 0.15), value: message.isEmpty)
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
            Group {
                switch sendState {
                case .idle:
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                        Text(L10n.contactSupportSend).font(.headline)
                    }
                case .sending:
                    ProgressView().tint(.black)
                case .success:
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: sendState == .success ? 60 : .infinity)
            .padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
        .disabled(sendState != .idle || !isMessageValid)
        .opacity(sendState == .idle && !isMessageValid ? 0.45 : 1)
        .shadow(color: theme.accent.opacity(sendState == .idle ? 0.35 : 0.15), radius: 16, y: 6)
        .modifier(ShakeEffect(animatableData: shakeTicks))
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: sendState)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
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
                try? await Task.sleep(for: .seconds(0.9))
                await MainActor.run {
                    viewModel.showSuccessToast(L10n.contactSupportSuccess)
                    dismiss()
                }
            }
        case .notConfigured:
            sendState = .idle
            errorMessage = L10n.contactSupportUnavailable
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .failure:
            sendState = .idle
            errorMessage = L10n.contactSupportError
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.linear(duration: 0.4)) { shakeTicks += 1 }
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

private extension View {
    /// Fade + rise into place, staggered by `delay` — used once per section
    /// on the sheet's initial appearance, driven by the shared `appeared` flag.
    func reveal(_ appeared: Bool, delay: Double) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(.easeOut(duration: 0.45).delay(delay), value: appeared)
    }

    /// Accent-colored border + soft glow while a field has focus.
    func fieldGlow(isActive: Bool, accent: Color) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? accent : Color.white.opacity(0.08), lineWidth: isActive ? 1.6 : 1)
        )
        .shadow(color: isActive ? accent.opacity(0.25) : .clear, radius: 10)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
