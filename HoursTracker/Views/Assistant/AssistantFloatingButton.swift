import SwiftUI
import UIKit

/// The floating assistant button that sits above every tab.
///
/// Tap opens the chat. Drag moves it — it snaps to whichever side it was let go nearest,
/// and the resting height is remembered. Press and hold for three seconds and a small X
/// appears beside it; tapping that hides the button, and the color picker turns it back
/// on. The icon is drawn in `HomeAccentTheme.shared.accent`, so it belongs to the app's
/// own identity rather than looking like a bolted-on AI widget.
struct AssistantFloatingButton: View {
    let onOpen: () -> Void
    let onHide: () -> Void

    var body: some View {
        GeometryReader { geo in
            PositionedAssistantButton(
                containerSize: geo.size,
                onOpen: onOpen,
                onHide: onHide
            )
        }
        // The keyboard must not shove the button up the screen; it is chrome, not content.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private struct PositionedAssistantButton: View {
    let containerSize: CGSize
    let onOpen: () -> Void
    let onHide: () -> Void

    @ObservedObject private var appearance = AssistantAppearance.shared
    @ObservedObject private var theme = HomeAccentTheme.shared
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false
    @State private var showsHideControl = false
    @State private var suppressTapAfterLongPress = false

    private static let diameter: CGFloat = 52
    private static let sideMargin: CGFloat = 16
    /// Enough clearance for the tab bar, including iOS 26's taller floating style.
    private static let bottomInset: CGFloat = 104
    private static let topInset: CGFloat = 28
    private static let hideControlTimeout: TimeInterval = 4

    var body: some View {
        icon
            .position(x: currentX, y: currentY)
            .animation(
                reduceMotion || isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.75),
                value: appearance.edge
            )
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(HomeNeon.card)
                .overlay(Circle().stroke(theme.accent.opacity(0.55), lineWidth: 1.5))
                .shadow(color: theme.accent.opacity(0.35), radius: isDragging ? 18 : 11, y: 4)

            Image(systemName: appearance.style.systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(theme.accent)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .scaleEffect(isDragging ? 1.08 : 1)
        .overlay(alignment: .topTrailing) {
            if showsHideControl {
                hideControl
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            guard !suppressTapAfterLongPress else { return }
            onOpen()
        }
        .onLongPressGesture(minimumDuration: 3) {
            revealHideControl()
        }
        .gesture(dragGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.assistantTitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: Text(L10n.assistantHideButton)) { onHide() }
    }

    private var hideControl: some View {
        Button {
            onHide()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(HomeNeon.coral))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .offset(x: 5, y: -5)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(L10n.assistantHideButton)
    }

    // MARK: - Position

    /// Where the button rests, before any in-flight drag is applied.
    private var restingX: CGFloat {
        let inset = Self.sideMargin + Self.diameter / 2
        let onLeft = (appearance.edge == .leading) == (layoutDirection == .leftToRight)
        return onLeft ? inset : containerSize.width - inset
    }

    private var restingY: CGFloat {
        containerSize.height - Self.bottomInset - Self.diameter / 2
            - verticalTravel * appearance.verticalOffset
    }

    /// How much vertical room the button has between the tab bar and the nav bar.
    private var verticalTravel: CGFloat {
        max(0, containerSize.height - Self.bottomInset - Self.topInset - Self.diameter)
    }

    private var currentX: CGFloat { restingX + dragTranslation.width }
    private var currentY: CGFloat { restingY + dragTranslation.height }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                isDragging = true
                dragTranslation = value.translation
            }
            .onEnded { value in
                let droppedX = restingX + value.translation.width
                let droppedY = restingY + value.translation.height

                let landedOnLeft = droppedX < containerSize.width / 2
                let leadingIsLeft = layoutDirection == .leftToRight
                let newEdge: AssistantIconEdge = (landedOnLeft == leadingIsLeft) ? .leading : .trailing

                let bottomAnchor = containerSize.height - Self.bottomInset - Self.diameter / 2
                let fraction = verticalTravel > 0 ? (bottomAnchor - droppedY) / verticalTravel : 0

                dragTranslation = .zero
                isDragging = false
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
                    appearance.edge = newEdge
                    appearance.verticalOffset = Double(fraction)
                }
            }
    }

    // MARK: - Hide affordance

    private func revealHideControl() {
        // The press ends in a touch-up that would otherwise read as a tap and open the
        // chat right after the X appears. Short-lived so a later real tap still works.
        suppressTapAfterLongPress = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            suppressTapAfterLongPress = false
        }

        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) {
            showsHideControl = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideControlTimeout) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                showsHideControl = false
            }
        }
    }
}
