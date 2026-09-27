import SwiftUI

/// Two-cell Gross | Net switch shared by the Day Summary and Home's live card.
///
/// Both screens bind the same `homePayDisplayMode` key, so a choice made in one
/// shows in the other (and on widgets / Watch / Live Activity via `onChange`).
/// With values the cells show both totals (Day Summary); without, they are a
/// compact 44pt switch under a hero figure (Home).
struct GrossNetSwitch: View {
    @Binding var mode: PayDisplayMode
    var grossValue: String?
    var netValue: String?
    let accent: Color
    /// Called after a real change (not on re-tapping the selected cell).
    var onChange: (PayDisplayMode) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            cell(.gross, title: AppLocale.tr("pay.gross"), value: grossValue)
            Rectangle().fill(DS.Palette.hairline).frame(width: 1).padding(.vertical, DS.Space.sm)
            cell(.net, title: AppLocale.tr("pay.net"), value: netValue)
        }
        .dsCard(radius: grossValue == nil ? DS.Radius.md : DS.Radius.lg)
        .sensoryFeedback(.selection, trigger: mode)
    }

    private func cell(_ cellMode: PayDisplayMode, title: String, value: String?) -> some View {
        let selected = mode == cellMode
        return Button {
            guard mode != cellMode else { return }
            withAnimation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion)) {
                mode = cellMode
            }
            onChange(cellMode)
        } label: {
            VStack(spacing: DS.Space.xxs) {
                Text(title)
                    .dsFont(value == nil ? .sub : .meta, weight: value == nil ? .semibold : nil)
                    .foregroundStyle(value == nil && selected ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                if let value {
                    Text(verbatim: value)
                        .htFont(size: 20, relativeTo: .title3, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: value == nil ? 44 : 64)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(selected ? accent.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(selected ? accent : .clear, lineWidth: 1.5)
            )
            .padding(DS.Space.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(cellMode == .net ? "payMode.net" : "payMode.gross")
    }
}
