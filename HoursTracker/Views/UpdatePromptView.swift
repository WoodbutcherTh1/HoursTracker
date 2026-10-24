import SwiftUI

/// "A new version is available": Update (opens the App Store page) or Later.
struct UpdatePromptPopup: View {
    let version: String
    let onUpdate: () -> Void
    let onLater: () -> Void
    @ObservedObject private var theme = HomeAccentTheme.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture(perform: onLater)
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(L10n.updatePromptTitle)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(String(format: L10n.updatePromptBody, version))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    Button(action: onUpdate) {
                        Text(L10n.updatePromptUpdate)
                            .font(.headline)
                            .foregroundStyle(Color.black.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(theme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("update.now")
                    Button(action: onLater) {
                        Text(L10n.updatePromptLater)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .accessibilityIdentifier("update.later")
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.08, blue: 0.10))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.08)))
            )
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 28)
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        }
        .accessibilityAddTraits(.isModal)
    }
}
