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
    /// Shifts the Undo brings back — more than one after a History multi-delete.
    var count: Int = 1
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(count > 1 ? L10n.historyShiftsDeleted(count) : L10n.feedbackSessionDeleted, systemImage: "trash")
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

/// Lets a bottom banner be pulled down to dismiss it, instead of waiting for its timer.
/// The banner follows the finger; past a short distance (or a quick flick) it goes,
/// otherwise it springs back.
struct SwipeDownToDismiss: ViewModifier {
    let onDismiss: () -> Void
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(1 - min(offset / 160, 0.6))
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        // Down follows the finger; up resists.
                        let dy = value.translation.height
                        offset = dy > 0 ? dy : dy / 6
                    }
                    .onEnded { value in
                        if value.translation.height > 40 || value.predictedEndTranslation.height > 110 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeOut(duration: 0.18)) { offset = 220 }
                            onDismiss()
                            offset = 0
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { offset = 0 }
                        }
                    }
            )
    }
}

extension View {
    func swipeDownToDismiss(_ onDismiss: @escaping () -> Void) -> some View {
        modifier(SwipeDownToDismiss(onDismiss: onDismiss))
    }
}
