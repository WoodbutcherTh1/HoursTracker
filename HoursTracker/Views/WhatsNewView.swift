import SwiftUI

/// The release-notes card: title with the new version, one swipeable card per
/// change (each icon in its own color from a small fixed cycle, so the deck
/// doesn't read as one monochrome list), a close X and a "Got it" button. Text
/// follows the in-app language (English by default).
struct WhatsNewCard: View {
    let release: WhatsNewRelease
    let onClose: () -> Void
    @State private var page = 0

    private var language: String { AppLocale.current.localeIdentifier }

    /// Fixed brand Cyan/Green, not the user's personalized `HomeAccentTheme` —
    /// this card is specifically announcing the new Cyan+Green theme, so it shows
    /// those two colors regardless of whatever accent the reader has customized.
    private static let cyan = Color(hex: "00E5FF")
    private static let green = Color(hex: "26F273")
    private static let cyanGreenGradient = LinearGradient(
        colors: [cyan, green],
        startPoint: .leading,
        endPoint: .trailing
    )
    /// Alternates by item index so consecutive cards never repeat the same color.
    private static let iconColors = [cyan, green]
    private func iconColor(at index: Int) -> Color { Self.iconColors[index % Self.iconColors.count] }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Self.cyanGreenGradient)
                    .padding(14)
                    .background(Circle().fill(Self.cyan.opacity(0.15)))
                    .accessibilityHidden(true)
                Text(String(format: L10n.whatsNewTitle, release.version))
                    .dsFont(.titleScreen)
                    .multilineTextAlignment(.center)
                Text(L10n.whatsNewSubtitle)
                    .dsFont(.sub)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(Array(release.items.enumerated()), id: \.element.id) { index, item in
                    whatsNewCardPage(item, color: iconColor(at: index))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: UIScreen.main.bounds.height * 0.42)

            if release.items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(release.items.indices, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Self.cyan : Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            // Counts down live: 22 hours left, then 21, … and gone for the last hour.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let hours = WhatsNewCenter.shared.hoursLeft(now: context.date) {
                    Text(String(format: L10n.whatsNewFindAgain, hours))
                        .dsFont(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onClose) {
                Text(L10n.whatsNewDone)
                    .font(.headline)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Self.cyanGreenGradient, in: Capsule())
            }
            .accessibilityIdentifier("whatsNew.done")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.06, green: 0.08, blue: 0.10))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.08)))
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .padding(12)
            .accessibilityLabel(L10n.whatsNewClose)
            .accessibilityIdentifier("whatsNew.close")
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func whatsNewCardPage(_ item: WhatsNewItem, color: Color) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(16)
                    .background(Circle().fill(color.opacity(0.15)))
                    .accessibilityHidden(true)
                Text(item.localizedTitle(language))
                    .dsFont(.headline)
                    .multilineTextAlignment(.center)
                Text(item.localizedText(language))
                    .dsFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = item.localizedSubtitle(language) {
                    Text(subtitle)
                        .dsFont(.caption)
                        .foregroundStyle(.secondary.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let nativeHighlight = item.nativeHighlight {
                    Text(nativeHighlight)
                        .font(.body.bold())
                        .foregroundColor(.cyan)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

/// The card over a dimmed app, for the first launch after an update.
struct WhatsNewPopup: View {
    let release: WhatsNewRelease
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture(perform: onClose)
            WhatsNewCard(release: release, onClose: onClose)
                .padding(.horizontal, 20)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// Same card as a sheet, for the About screen's "What's new" row.
struct WhatsNewSheet: View {
    let release: WhatsNewRelease
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WhatsNewCard(release: release) { dismiss() }
            .padding(20)
            .presentationDetents([.large])
            .presentationBackground(Color.black)
    }
}
