import SwiftUI

/// The release-notes card: title with the new version, one row per change, a close X
/// and a "Got it" button. Text follows the in-app language (English by default).
struct WhatsNewCard: View {
    let release: WhatsNewRelease
    let onClose: () -> Void
    @ObservedObject private var theme = HomeAccentTheme.shared

    private var language: String { AppLocale.current.localeIdentifier }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(14)
                    .background(Circle().fill(theme.accent.opacity(0.15)))
                    .accessibilityHidden(true)
                Text(String(format: L10n.whatsNewTitle, release.version))
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(L10n.whatsNewSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(release.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.localizedTitle(language)).font(.subheadline.weight(.semibold))
                                Text(item.localizedText(language))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.5)

            // Counts down live: 22 hours left, then 21, … and gone for the last hour.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let hours = WhatsNewCenter.shared.hoursLeft(now: context.date) {
                    Text(String(format: L10n.whatsNewFindAgain, hours))
                        .font(.caption)
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
                    .background(theme.accent, in: Capsule())
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
