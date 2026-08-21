import SwiftUI

/// Compact sheet for customizing the app's accent color, background color, Home title
/// and Home card layout — presets plus a full picker for anything else.
///
/// Every control here previews itself: the values are `@Published` on shared theme
/// objects, so picking a background repaints this sheet along with the rest of the app,
/// and the wordmark row is the real `HomeBrandTitle`. There is nothing to confirm.
struct HomeThemePickerSheet: View {
    @ObservedObject var theme: HomeAccentTheme
    @ObservedObject private var statsLayout = HomeStatsLayout.shared
    @ObservedObject private var wordmark = HomeWordmark.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        preview

                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.homeThemePresets)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(HomeAccentTheme.presets, id: \.hex) { preset in
                                    swatch(hex: preset.hex, name: preset.name)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.homeThemeCustom)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))

                            ColorPicker(L10n.homeThemeCustom, selection: $theme.accent, supportsOpacity: false)
                                .labelsHidden()
                                .padding(12)
                                .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.homeThemeBackground)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(AppBackgroundTheme.presets, id: \.hex) { preset in
                                    backgroundSwatch(
                                        hex: preset.hex,
                                        name: AppBackgroundTheme.localizedPresetName(preset.name)
                                    )
                                }
                            }

                            ColorPicker(
                                L10n.homeThemeBackground,
                                selection: $appBackground.background,
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            .padding(12)
                            .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.homeThemeWordmark)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))

                            TextField(
                                L10n.homeThemeWordmarkPlaceholder,
                                text: $wordmark.text
                            )
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .foregroundStyle(.white)
                            .tint(theme.accent)
                            .padding(12)
                            .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text(L10n.homeThemeWordmarkHint)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.homeStatsCardsTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))

                            VStack(spacing: 8) {
                                ForEach(Array(statsLayout.order.enumerated()), id: \.offset) { index, metric in
                                    cardSlotRow(index: index, metric: metric)
                                }
                            }
                        }

                        Button(role: .destructive) {
                            theme.reset()
                        } label: {
                            Text(L10n.homeThemeReset)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeNeon.coral)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule(style: .continuous)
                                        .stroke(HomeNeon.coral.opacity(0.5), lineWidth: 1.2)
                                )
                        }

                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.2)) { appBackground.reset() }
                        } label: {
                            Text(L10n.homeThemeBackgroundReset)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeNeon.coral)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule(style: .continuous)
                                        .stroke(HomeNeon.coral.opacity(0.5), lineWidth: 1.2)
                                )
                        }

                        Button(role: .destructive) {
                            statsLayout.reset()
                        } label: {
                            Text(L10n.homeStatsResetOrder)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeNeon.coral)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule(style: .continuous)
                                        .stroke(HomeNeon.coral.opacity(0.5), lineWidth: 1.2)
                                )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(L10n.homeThemeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(appBackground.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.summaryDone) { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    /// Live preview of everything this sheet changes. The wordmark row is the real
    /// `HomeBrandTitle` rather than a mock-up, so what you see here is exactly what the
    /// Home navigation bar will render.
    private var preview: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(theme.accent.opacity(0.18))
                .frame(width: 84, height: 84)
                .overlay(
                    Circle()
                        .stroke(theme.accent, lineWidth: 2)
                )
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(theme.accent)
                )
                .shadow(color: theme.accent.opacity(0.4), radius: 20)

            HomeBrandTitle(accent: theme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(HomeNeon.card, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func cardSlotRow(index: Int, metric: HomeStatMetric) -> some View {
        Menu {
            ForEach(HomeStatMetric.allCases) { option in
                Button {
                    statsLayout.setMetric(option, at: index)
                } label: {
                    if option == metric {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack {
                Text("\(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 18)
                Text(metric.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(12)
            .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// Background swatches carry a hairline ring rather than relying on the fill alone —
    /// several of these colors are near-black and would otherwise be indistinguishable
    /// from the sheet they sit on.
    private func backgroundSwatch(hex: String, name: String) -> some View {
        let color = Color(hex: hex)
        let isSelected = appBackground.background.hexString == hex

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appBackground.background = color
            }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color)
                    .frame(width: 44, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isSelected ? theme.accent : Color.white.opacity(0.18),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                    .overlay(
                        // A miniature card, so the swatch shows how much contrast the
                        // app's surfaces will actually have on this background.
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(HomeNeon.card)
                            .frame(width: 22, height: 14)
                    )
                    .shadow(color: theme.accent.opacity(isSelected ? 0.45 : 0), radius: 8)

                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func swatch(hex: String, name: String) -> some View {
        let color = Color(hex: hex)
        let isSelected = theme.accent.hexString == hex

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                theme.accent = color
            }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(.white, lineWidth: isSelected ? 2.5 : 0)
                    )
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.4), lineWidth: isSelected ? 6 : 0)
                            .blur(radius: 4)
                    )
                    .shadow(color: color.opacity(isSelected ? 0.6 : 0), radius: 8)

                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
