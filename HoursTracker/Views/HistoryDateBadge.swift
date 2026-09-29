import SwiftUI

/// The date / weekday label on each History row, drawn as a small Liquid Glass
/// capsule. iOS 26 uses the system glass; earlier versions a thin material with a
/// hairline that reads the same.
///
/// In multi-select mode a selected row's capsule fills with the accent and shows
/// a checkmark, so the capsule doubles as the row's selection indicator.
struct HistoryDateBadge: View {
    let text: String
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(verbatim: text)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background { DateBadgeGlass(isSelected: isSelected) }
        .contentShape(Capsule())
    }
}

private struct DateBadgeGlass: View {
    let isSelected: Bool

    var body: some View {
        let shape = Capsule()
        Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        isSelected ? .regular.tint(Color.accentColor.opacity(0.85)) : .regular,
                        in: shape
                    )
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(isSelected ? Color.accentColor : DS.Palette.card.opacity(0.35)))
            }
        }
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
        )
    }
}
