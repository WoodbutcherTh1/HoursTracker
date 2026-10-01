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
    @Environment(\.layoutDirection) private var layoutDirection
    /// Finger offset while dragging the thumb; 0 when at rest.
    @State private var dragX: CGFloat = 0
    @State private var cellWidth: CGFloat = 0

    private var isCompact: Bool { grossValue == nil }
    private var trackRadius: CGFloat { isCompact ? 22 : DS.Radius.lg + 4 }
    private var thumbRadius: CGFloat { isCompact ? 18 : DS.Radius.lg }

    /// A soft spring for the slide — settles without a visible bounce.
    private var slide: Animation {
        reduceMotion ? DS.Motion.reduced : .spring(response: 0.38, dampingFraction: 0.82)
    }

    /// Left-to-right order on screen. The switch lays out in LTR internally so the
    /// drag math is plain; RTL languages get Gross on the right, as before.
    private var order: [PayDisplayMode] {
        layoutDirection == .rightToLeft ? [.net, .gross] : [.gross, .net]
    }

    private var selectedIndex: CGFloat {
        CGFloat(order.firstIndex(of: mode) ?? 0)
    }

    /// Thumb's x inside the track, following the finger and clamped to the cells.
    private var thumbX: CGFloat {
        min(max(selectedIndex * cellWidth + dragX, 0), cellWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(order, id: \.self) { cellMode in
                if cellMode == .gross {
                    cell(.gross, title: AppLocale.tr("pay.gross"), value: grossValue)
                } else {
                    cell(.net, title: AppLocale.tr("pay.net"), value: netValue)
                }
            }
        }
        .background(alignment: .leading) {
            GlassThumb(radius: thumbRadius, accent: accent)
                .frame(width: cellWidth)
                .offset(x: thumbX)
                .opacity(cellWidth > 0 ? 1 : 0)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { cellWidth = proxy.size.width / 2 }
                    .onChange(of: proxy.size.width) { _, width in cellWidth = width / 2 }
            }
        }
        .padding(DS.Space.xxs)
        .background { GlassTrack(radius: trackRadius) }
        .environment(\.layoutDirection, .leftToRight)
        // Drag the thumb with a finger; it snaps to the nearer cell on release
        // (a quick flick counts). Taps still go to the cells.
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    dragX = drag.translation.width
                }
                .onEnded { drag in
                    guard cellWidth > 0,
                          abs(drag.translation.width) > abs(drag.translation.height) else {
                        withAnimation(slide) { dragX = 0 }
                        return
                    }
                    let end = selectedIndex * cellWidth + drag.predictedEndTranslation.width
                    let target = order[end > cellWidth / 2 ? 1 : 0]
                    let changed = mode != target
                    withAnimation(slide) {
                        dragX = 0
                        mode = target
                    }
                    if changed { notifyAfterSlide(target) }
                }
        )
        .sensoryFeedback(.selection, trigger: mode)
    }

    private func select(_ newMode: PayDisplayMode) {
        guard mode != newMode else { return }
        withAnimation(slide) {
            mode = newMode
        }
        notifyAfterSlide(newMode)
    }

    /// The caller's onChange pushes the choice to widgets, Watch and the Live
    /// Activity. Run it once the spring has settled so that work can't make the
    /// slide stutter.
    private func notifyAfterSlide(_ newMode: PayDisplayMode) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onChange(newMode)
        }
    }

    private func cell(_ cellMode: PayDisplayMode, title: String, value: String?) -> some View {
        let selected = mode == cellMode
        return Button {
            select(cellMode)
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
                    .glassEffect(.regular.tint(accent.opacity(0.28)), in: shape)
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
