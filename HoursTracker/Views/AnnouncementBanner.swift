import SwiftUI

/// Owner announcement, shown once as a center overlay until the user picks
/// "Later" or "Open" (see `AnnouncementCenter`). Replaces the old top banner —
/// a dimmed + blurred backdrop focuses attention the way a top banner, easy to
/// glance past, didn't.
struct AnnouncementCenterOverlay: View {
    let announcement: Announcement
    let onLater: () -> Void
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private static let cyan = Color(hex: "00E5FF")
    private static let green = Color(hex: "26F273")
    private static let cyanGreenGradient = LinearGradient(
        colors: [cyan, green],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// First couple of lines only — the full text is one tap away in the details sheet.
    private var snippet: String {
        let lines = announcement.body.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.prefix(2).joined(separator: " ")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
        .onTapGesture(perform: onLater)
        .overlay {
            card
                .padding(.horizontal, DS.Space.xl)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }

    private var card: some View {
        VStack(spacing: DS.Space.lg) {
            ZStack {
                Circle()
                    .fill(Self.cyanGreenGradient.opacity(0.18))
                    .frame(width: 72, height: 72)
                    .blur(radius: 10)
                Circle()
                    .fill(Self.cyanGreenGradient)
                    .frame(width: 56, height: 56)
                    .shadow(color: Self.cyan.opacity(0.45), radius: 16, y: 4)
                Image(systemName: "megaphone.fill")
                    .htFont(size: 22, relativeTo: .title2, weight: .semibold)
                    .foregroundStyle(.black.opacity(0.85))
            }
            .accessibilityHidden(true)

            VStack(spacing: DS.Space.xs) {
                Text(L10n.announcementHeader)
                    .dsFont(.sectionHeader)
                    .foregroundStyle(DS.Palette.textTertiary)
                if !announcement.title.isEmpty {
                    Text(verbatim: announcement.title)
                        .dsFont(.titleSection)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .multilineTextAlignment(.center)
                }
                Text(verbatim: snippet)
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DS.Space.sm) {
                Button(action: onLater) {
                    Text(L10n.announcementLater)
                        .dsFont(.headline)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(DS.Palette.hairline, lineWidth: 1)
                )
                .accessibilityIdentifier("announcement.later")

                Button(action: openTapped) {
                    Text(L10n.announcementOpen)
                        .dsFont(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .background(Self.cyanGreenGradient, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .accessibilityIdentifier("announcement.open")
            }
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: 360)
        .dsCard(radius: DS.Radius.xl, fill: DS.Palette.card)
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }

    private func openTapped() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onOpen()
    }
}

/// Full text + developer interactions, one tap away from the center overlay's "Open".
struct AnnouncementDetailsSheet: View {
    let announcement: Announcement
    let onReplyToDeveloper: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @State private var reaction: Reaction?
    @State private var isSendingReaction = false

    private enum Reaction { case liked, disliked }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    if !announcement.title.isEmpty {
                        Text(verbatim: announcement.title)
                            .dsFont(.titleScreen)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // SwiftUI's Markdown-aware `Text` initializer renders `[label](url)`
                    // links as tappable, without a WebView or a Markdown dependency.
                    Text(.init(announcement.body))
                        .dsFont(.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .tint(homeTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().overlay(DS.Palette.hairline)

                    reactionRow

                    Button(action: onReplyToDeveloper) {
                        Label(L10n.announcementReplyToDeveloper, systemImage: "bubble.left.and.bubble.right.fill")
                            .dsFont(.headline)
                            .foregroundStyle(homeTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .stroke(homeTheme.accent.opacity(0.4), lineWidth: 1)
                    )
                    .accessibilityIdentifier("announcement.replyToDeveloper")
                }
                .padding(DS.Space.lg)
            }
            .navigationTitle(L10n.announcementDetailsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.announcementDismiss) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var reactionRow: some View {
        if let reaction {
            Label(L10n.announcementFeedbackThanks, systemImage: "checkmark.circle.fill")
                .dsFont(.sub, weight: .semibold)
                .foregroundStyle(DS.Palette.success)
                .accessibilityIdentifier(reaction == .liked ? "announcement.like.confirmed" : "announcement.dislike.confirmed")
        } else {
            HStack(spacing: DS.Space.sm) {
                reactionButton(.liked, icon: "hand.thumbsup.fill", title: L10n.announcementLike)
                reactionButton(.disliked, icon: "hand.thumbsdown.fill", title: L10n.announcementDislike)
            }
            .opacity(isSendingReaction ? 0.5 : 1)
            .disabled(isSendingReaction)
        }
    }

    private func reactionButton(_ value: Reaction, icon: String, title: String) -> some View {
        Button {
            send(value)
        } label: {
            Label(title, systemImage: icon)
                .dsFont(.sub, weight: .semibold)
                .foregroundStyle(DS.Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Palette.raised)
        )
        .accessibilityIdentifier(value == .liked ? "announcement.like" : "announcement.dislike")
    }

    /// Not local `@State` only — a real signal to the developer, through the same
    /// Edge Function Contact Support uses, tagged with which announcement and verdict.
    private func send(_ value: Reaction) {
        isSendingReaction = true
        let title = announcement.title.isEmpty ? announcement.body : announcement.title
        let verdict = value == .liked ? "אהבתי" : "לא אהבתי"
        let text = "תגובה להודעה: \(title) - \(verdict)"
        Task {
            let result = await TelegramFeedbackSender.send(text)
            await MainActor.run {
                isSendingReaction = false
                if result == .success {
                    reaction = value
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }
}
