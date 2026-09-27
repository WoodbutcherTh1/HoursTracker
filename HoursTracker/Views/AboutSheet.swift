import SwiftUI
import UIKit

/// Opened from the brand mark on Home (`.medium` detent only).
///
/// The mark is the same hourglass symbol as the greeting row — no bitmap copy of
/// the app icon. The version comes from the bundle, never typed in. The wordmark
/// (custom or not) still shows here now that Home's toolbar no longer carries it.
struct AboutSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.openURL) private var openURL
    @State private var showUserGuide = false
    @State private var showPrivacy = false
    @State private var showHelp = false
    @State private var toast: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let reviewURL = URL(string: "https://apps.apple.com/app/id6790862413?action=write-review")

    static var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.lg) {
                header

                if Self.reviewURL != nil {
                    Button(action: rate) {
                        Label(L10n.settingsRateApp, systemImage: "star.fill")
                    }
                    .buttonStyle(DSPrimaryButtonStyle(accent: theme.accent))
                }

                VStack(spacing: 0) {
                    row(L10n.guideTitle, icon: "book.fill", id: "about.guide") { showUserGuide = true }
                    divider
                    row(L10n.privacyTitle, icon: "hand.raised.fill", id: "about.privacy") { showPrivacy = true }
                    divider
                    row(L10n.homeHelpFeedback, icon: "bubble.left.and.text.bubble.right.fill", id: "about.help") { showHelp = true }
                }
                .dsCard(radius: DS.Radius.lg)

                Text(L10n.aboutMadeIn)
                    .dsFont(.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(appBackground.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showUserGuide) {
            UserGuideSheet(workerName: viewModel.settings.workerFullName)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack { PrivacyPolicyView() }
        }
        .sheet(isPresented: $showHelp) {
            ContactSupportSheet(viewModel: viewModel)
        }
        .overlay(alignment: .bottom) { toastView }
        .accessibilityIdentifier("about.sheet")
    }

    /// Opens the App Store review page. Where it can't open (the simulator has no
    /// App Store; a device may refuse), a thank-you toast instead — the button
    /// never looks broken.
    private func rate() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #if targetEnvironment(simulator)
        showToast(L10n.aboutRateThanks)
        #else
        guard let url = Self.reviewURL else { return }
        openURL(url) { accepted in
            if !accepted { showToast(L10n.aboutRateThanks) }
        }
        #endif
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .dsFont(.sub, weight: .semibold)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
                .background(Capsule(style: .continuous).fill(DS.Palette.raised))
                .padding(.bottom, DS.Space.lg)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityIdentifier("about.toast")
        }
    }

    private func showToast(_ text: String) {
        withAnimation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion)) { toast = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion)) { toast = nil }
        }
    }

    private var header: some View {
        VStack(spacing: DS.Space.sm) {
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(theme.accent.opacity(0.15))
                .overlay(
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(theme.accent)
                )
                .frame(width: 80, height: 80)
                .background(DSHeroGlow(color: theme.accent))
                .accessibilityHidden(true)
            HomeBrandTitle(accent: theme.accent)
            Text(verbatim: Self.versionString)
                .dsFont(.meta)
                .foregroundStyle(DS.Palette.textTertiary)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel("\(L10n.settingsVersion) \(Self.versionString)")
        }
    }

    private var divider: some View {
        Rectangle().fill(DS.Palette.hairline).frame(height: 1).padding(.leading, 52)
    }

    private func row(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: icon)
                    .htFont(size: 17, relativeTo: .body, weight: .semibold)
                    .foregroundStyle(theme.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: DS.Space.xs)
                Image(systemName: "chevron.forward")
                    .htFont(size: 13, relativeTo: .footnote, weight: .semibold)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
