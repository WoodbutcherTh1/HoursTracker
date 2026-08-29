import SwiftUI

/// "Days worked" figure for History, with the green `+1?` bubble that appears while a
/// shift is running on a day that has not been counted yet.
///
/// Both the number and the bubble come from `WorkedDaysCounter` — this view holds no
/// counting logic of its own, so the copy shown in History's summary bar and the one in
/// the pay-breakdown sheet can never drift apart.
struct WorkedDaysBadge: View {
    let dayCount: Int
    /// True when clocking out right now would push `dayCount` up by one.
    let showsPendingDay: Bool
    var alignment: HorizontalAlignment = .trailing
    var valueFont: Font = .subheadline.weight(.semibold).monospacedDigit()
    /// Off where the surrounding row already carries the "Days worked" label.
    var showsTitle: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            if showsTitle {
                Text(L10n.historyDaysWorked)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 5) {
                Text("\(dayCount)")
                    .font(valueFont)
                    .contentTransition(.numericText())

                if showsPendingDay {
                    PendingDayBubble(reduceMotion: reduceMotion)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: dayCount)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: showsPendingDay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let base = L10n.historyDaysWorkedAccessibility(dayCount)
        return showsPendingDay ? base + ", " + L10n.historyDaysWorkedPendingHint : base
    }
}

/// The `+1?` bubble itself: pops in on a spring, then keeps hopping gently so it reads as
/// "not final yet" rather than as part of the number. Green regardless of the accent
/// color — like the coral "clocked in" door, it carries a fixed meaning (a gain that is
/// about to land), not decoration.
private struct PendingDayBubble: View {
    let reduceMotion: Bool

    @State private var isHopping = false

    var body: some View {
        Text(verbatim: "+1?")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.green.gradient, in: Capsule())
            .offset(y: isHopping ? -3.5 : 0)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    isHopping = true
                }
            }
            .onDisappear { isHopping = false }
    }
}
