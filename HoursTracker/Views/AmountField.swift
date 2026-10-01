import SwiftUI

/// Decimal-pad amount field whose digits are drawn by SwiftUI `Text`.
///
/// BUG #1: in Hebrew/Arabic the rate `TextField` stored the typed digits but drew
/// nothing, only the caret, with or without a forced `.leftToRight`. The real
/// `TextField` is kept for input, focus, VoiceOver and UI tests, with clear text
/// and caret; the number and a caret are drawn on top of it. The digits stay in
/// typing order (the number group is left-to-right), and in Hebrew/Arabic the
/// group sits on the leading side, next to ₪ on the right.
struct AmountField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let size: CGFloat
    let textStyle: Font.TextStyle
    let weight: Font.Weight
    let accent: Color
    let accessibilityLabel: String
    let identifier: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TextField("", text: $text)
            .keyboardType(.decimalPad)
            .focused(focus)
            .htFont(size: size, relativeTo: textStyle, weight: weight, design: .rounded)
            .foregroundStyle(.clear)
            .tint(.clear)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(identifier)
            .overlay(alignment: .leading) {
                drawnNumber
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    private var drawnNumber: some View {
        HStack(spacing: 2) {
            if text.isEmpty {
                if focus.wrappedValue { caret }
                digits("0", color: DS.Palette.textTertiary)
            } else {
                digits(text, color: DS.Palette.textPrimary)
                if focus.wrappedValue { caret }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func digits(_ value: String, color: Color) -> some View {
        Text(verbatim: value)
            .htFont(size: size, relativeTo: textStyle, weight: weight, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// Blinks like the system caret; steady under Reduce Motion.
    private var caret: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
            let on = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3, height: size * 0.85)
                .opacity(on ? 1 : 0)
        }
        .frame(width: 3)
    }
}
