import SwiftUI

/// First-launch onboarding: explains the three core promises of the app
/// (effortless time tracking, correct Israeli pay rules, privacy-first data)
/// before dropping the user into the Home screen. Presented once via
/// `MainTabView`'s full-screen cover and remembered with `@AppStorage`.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appLanguage: AppLanguageController
    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @State private var page = 0
    private let totalPages = 3

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            TabView(selection: $page) {
                pageView(
                    systemImage: "clock.badge.checkmark",
                    title: L10n.onboardingStep1Title,
                    body: L10n.onboardingStep1Body,
                    tag: 0
                )
                pageView(
                    systemImage: "banknote.fill",
                    title: L10n.onboardingStep2Title,
                    body: L10n.onboardingStep2Body,
                    tag: 1
                )
                pageView(
                    systemImage: "lock.shield.fill",
                    title: L10n.onboardingStep3Title,
                    body: L10n.onboardingStep3Body,
                    tag: 2
                )
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: page)

            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? homeTheme.accent : Color.white.opacity(0.2))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }
            .padding(.top, 28)

            // Continue / Start
            Button {
                if page < totalPages - 1 {
                    withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
                } else {
                    // Dismissal sets `hasSeenOnboarding` via the cover binding.
                    dismiss()
                }
            } label: {
                Text(page < totalPages - 1 ? L10n.onboardingNext : L10n.onboardingStart)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(homeTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackground.background.ignoresSafeArea())
        .environment(\.layoutDirection, appLanguage.layoutDirection)
    }

    private func pageView(systemImage: String, title: String, body: String, tag: Int) -> some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .fill(homeTheme.accent.opacity(0.12))
                    .frame(width: 140, height: 140)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [homeTheme.accent.opacity(0.5), homeTheme.accent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 158, height: 158)
                Image(systemName: systemImage)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [homeTheme.accent, Color.cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.bottom, 8)

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(body)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 34)
            }
            Spacer(minLength: 60)
        }
        .tag(tag)
    }
}