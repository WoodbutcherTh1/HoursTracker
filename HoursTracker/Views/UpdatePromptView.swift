import SwiftUI

/// "A new version is available": Update (opens the App Store page) or Later.
///
/// Styled as a bottom sheet — bottom-anchored, rounded only at the top corners,
/// a drag-handle capsule, sliding up from the edge — rather than a centered
/// card, so it reads the way the rest of iOS presents a lightweight choice.
/// Still presented via the same app-launch `.overlay` `HoursTrackerApp` already
/// uses for `WhatsNewPopup`/announcements (not a `.sheet`), so it stays in step
/// with that shared sequencing instead of competing with it for presentation.
struct UpdatePromptPopup: View {
    let version: String
    let onUpdate: () -> Void
    let onLater: () -> Void

    /// Fixed Neon Cyan, not the personalized accent — the brief calls for this
    /// one button specifically, same as Export's gradient CTA.
    private static let cyan = Color(hex: "00E5FF")

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture(perform: onLater)

            VStack(spacing: 16) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Self.cyan)
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
                            .background(Self.cyan, in: Capsule())
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
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.08, blue: 0.10))
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08))
                    )
            )
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea(edges: .bottom)
            .shadow(color: .black.opacity(0.4), radius: 24, y: -4)
            .transition(.move(edge: .bottom))
        }
        .accessibilityAddTraits(.isModal)
    }
}
