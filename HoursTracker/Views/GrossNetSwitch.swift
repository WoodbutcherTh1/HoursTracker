import SwiftUI

/// Two-cell Gross | Net switch shared by the Day Summary and Home's live card.
///
/// Both screens bind the same `homePayDisplayMode` key, so a choice made in one
/// shows in the other (and on widgets / Watch / Live Activity via `onChange`).
/// With values the cells show both totals (Day Summary); without, they are a
/// compact 44pt switch under a hero figure (Home).
///
/// Liquid Glass: a glass track with one glass "thumb" that slides between the
/// cells (a single view moved with `matchedGeometryEffect`, not two highlights
/// fading). iOS 26 uses the system glass; earlier versions a material + hairline
/// that reads the same. Reduce Motion swaps the slide for a quick cross-fade.
struct GrossNetSwitch: View {
    @Binding var mode: PayDisplayMode
    var grossValue: String?
    var netValue: String?
    let accent: Color
    /// Called after a real change (not on re-tapping the selected cell).
    var onChange: (PayDisplayMode) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumbSpace

    private var isCompact: Bool { grossValue == nil }
    private var trackRadius: CGFloat { isCompact ? 22 : DS.Radius.lg + 4 }
    private var thumbRadius: CGFloat { isCompact ? 18 : DS.Radius.lg }

    /// A soft spring for the slide — settles without a visible bounce.
    private var slide: Animation {
        reduceMotion ? DS.Motion.reduced : .spring(response: 0.38, dampingFraction: 0.82)
    }

    var body: some View {
        HStack(spacing: 0) {
            cell(.gross, title: AppLocale.tr("pay.gross"), value: grossValue)
            cell(.net, title: AppLocale.tr("pay.net"), value: netValue)
        }
        .padding(DS.Space.xxs)
        .background { GlassTrack(radius: trackRadius) }
        .sensoryFeedback(.selection, trigger: mode)
    }

    private func cell(_ cellMode: PayDisplayMode, title: String, value: String?) -> some View {
        let selected = mode == cellMode
        return Button {
            guard mode != cellMode else { return }
            withAnimation(slide) {
                mode = cellMode
            }
            onChange(cellMode)
        } label: {
            VStack(spacing: DS.Space.xxs) {
                Text(title)
                    .dsFont(value == nil ? .sub : .meta, weight: value == nil ? .semibold : nil)
                    .foregroundStyle(selected ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                if let value {
                    Text(verbatim: value)
                        .htFont(size: 20, relativeTo: .title3, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight)
                        .foregroundStyle(selected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: value == nil ? 40 : 60)
            .background {
                if selected {
                    GlassThumb(radius: thumbRadius, accent: accent)
                        .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                        .transition(reduceMotion ? .opacity : .identity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(cellMode == .net ? "payMode.net" : "payMode.gross")
    }
}

/// The switch's track: system Liquid Glass on iOS 26, a thin material before.
private struct GlassTrack: View {
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(DS.Palette.card.opacity(0.35)))
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
    }
}

/// The sliding selection: accent-tinted glass with a bright top edge.
private struct GlassThumb: View {
    let radius: CGFloat
    let accent: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(accent.opacity(0.28)).interactive(), in: shape)
            } else {
                shape
                    .fill(.thinMaterial)
                    .overlay(shape.fill(accent.opacity(0.16)))
            }
        }
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.45), accent.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
        .shadow(color: accent.opacity(0.25), radius: 8, y: 2)
    }
}
