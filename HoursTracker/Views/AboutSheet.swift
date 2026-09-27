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

                if let url = Self.reviewURL {
                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        openURL(url)
                    } label: {
                        Label(L10n.settingsRateApp, systemImage: "star.fill")
                    }
                    .buttonStyle(DSPrimaryButtonStyle(accent: theme.accent))
                }

                VStack(spacing: 0) {
                    row(L10n.guideTitle, icon: "book.fill") { showUserGuide = true }
                    divider
                    row(L10n.privacyTitle, icon: "hand.raised.fill") { showPrivacy = true }
                    divider
                    row(L10n.homeHelpFeedback, icon: "bubble.left.and.text.bubble.right.fill") { showHelp = true }
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
        .accessibilityIdentifier("about.sheet")
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

    private func row(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
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
    }
}
