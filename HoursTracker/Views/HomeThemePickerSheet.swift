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
    @ObservedObject private var assistant = AssistantAppearance.shared
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
                        accentSection
                        backgroundSection
                        wordmarkSection
                        assistantSection
                        cardsSection
                        resetSection
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

    // MARK: - Sections

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.homeThemePresets)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(HomeAccentTheme.presets, id: \.hex) { preset in
                    swatch(hex: preset.hex, name: preset.name)
                }
            }

            sectionTitle(L10n.homeThemeCustom)

            ColorPicker(L10n.homeThemeCustom, selection: $theme.accent, supportsOpacity: false)
                .labelsHidden()
                .padding(12)
                .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.homeThemeBackground)

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
    }

    private var wordmarkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.homeThemeWordmark)

            TextField(L10n.homeThemeWordmarkPlaceholder, text: $wordmark.text)
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
    }

    private var assistantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.assistantSettingsTitle)

            Toggle(L10n.assistantSettingsEnabled, isOn: $assistant.isVisible.animation())
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(theme.accent)
                .padding(12)
                .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if assistant.isVisible {
                HStack(spacing: 10) {
                    ForEach(AssistantIconStyle.allCases) { style in
                        assistantStyleSwatch(style)
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        assistant.resetPosition()
                    }
                } label: {
                    Text(L10n.assistantSettingsResetPosition)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.homeStatsCardsTitle)

            VStack(spacing: 8) {
                ForEach(Array(statsLayout.order.enumerated()), id: \.offset) { index, metric in
                    cardSlotRow(index: index, metric: metric)
                }
            }
        }
    }

    private var resetSection: some View {
        VStack(spacing: 12) {
            resetButton(L10n.homeThemeReset) { theme.reset() }
            resetButton(L10n.homeThemeBackgroundReset) {
                withAnimation(.easeInOut(duration: 0.2)) { appBackground.reset() }
            }
            resetButton(L10n.homeStatsResetOrder) { statsLayout.reset() }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    private func resetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Text(title)
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

    /// Icon choice for the floating assistant button, drawn the way it will actually
    /// appear — accent-colored on the app's card surface, not as a plain symbol list.
    private func assistantStyleSwatch(_ style: AssistantIconStyle) -> some View {
        let isSelected = assistant.style == style

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                assistant.style = style
            }
        } label: {
            Image(systemName: style.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(HomeNeon.card)
                        .overlay(
                            Circle().stroke(
                                isSelected ? theme.accent : Color.white.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                        )
                )
                .shadow(color: theme.accent.opacity(isSelected ? 0.4 : 0), radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
