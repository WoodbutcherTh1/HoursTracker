import SwiftUI

/// In-app prompt shown when the owner has answered the user's support chat.
/// "Open" goes straight to the conversation (see `SupportInbox`).
struct SupportReplyBanner: View {
    let preview: String?
    let onOpen: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.supportReplyTitle, systemImage: "bubble.left.and.bubble.right.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let preview, !preview.isEmpty {
                Text(verbatim: preview)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button(L10n.supportReplyLater, action: onLater)
                    .font(.subheadline)
                Button(action: onOpen) {
                    Text(L10n.supportReplyOpen)
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("support.reply.open")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}
