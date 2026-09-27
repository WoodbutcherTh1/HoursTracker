import SwiftUI

/// Short-lived bottom confirmation used for successful user actions.
struct SuccessToastBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// "Shift deleted — Undo" shown for a few seconds after a delete. The shift also
/// stays in Settings → Recently deleted for 30 days.
struct UndoDeleteBanner: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(L10n.feedbackSessionDeleted, systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text(L10n.undoDelete)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .padding(.horizontal, 16)
    }
}
