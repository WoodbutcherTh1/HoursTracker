import SwiftUI
import UIKit

/// Top of Home, shared by the clocked-out and clocked-in screens:
/// [brand mark → About] greeting … [palette → theme picker].
///
/// The palette sits here rather than in a toolbar menu because the colour picker
/// lives on being found. After the first shift a one-time tip points at it until
/// the picker has been opened once.
struct HomeGreetingRow: View {
    /// Worker name from Settings; blank → the plain greeting, no name.
    let name: String?
    let accent: Color
    var compact: Bool = false
    var showThemeTip: Bool = false
    let onBrandTap: () -> Void
    let onThemeTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.sm) {
                brandMark
                greeting
                Spacer(minLength: 0)
                themeButton
            }
            if showThemeTip {
                themeTip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var greeting: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let title = DaypartGreeting.current(at: context.date, calendar: calendar).title(withName: name)
            Text(title)
                .htFont(size: compact ? 20 : 24, relativeTo: .title2, weight: .bold)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var brandMark: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onBrandTap()
        } label: {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(accent.opacity(0.15))
                .overlay(
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .symbolRenderingMode(.hierarchical)
                        .htFont(size: 15, relativeTo: .subheadline, weight: .semibold)
                        .foregroundStyle(accent)
                )
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressButtonStyle())
        .accessibilityLabel(L10n.homeAboutOpen)
        .accessibilityIdentifier("home.brandMark")
    }

    private var themeButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onThemeTap()
        } label: {
            Image(systemName: "paintpalette")
                .htFont(size: 22, relativeTo: .title3, weight: .medium)
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressButtonStyle())
        .accessibilityLabel(L10n.homeThemeTitle)
        .accessibilityIdentifier("home.themeButton")
    }

    private var themeTip: some View {
        Button(action: onThemeTap) {
            HStack(spacing: DS.Space.xxs) {
                Image(systemName: "arrow.up")
                    .htFont(size: 12, relativeTo: .footnote, weight: .bold)
                    .accessibilityHidden(true)
                Text(L10n.homeThemeTip)
                    .dsFont(.meta, weight: .semibold)
            }
            .foregroundStyle(DS.Palette.ink)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xxs + 2)
            .background(Capsule(style: .continuous).fill(accent))
        }
        .buttonStyle(ScalePressButtonStyle())
    }
}
