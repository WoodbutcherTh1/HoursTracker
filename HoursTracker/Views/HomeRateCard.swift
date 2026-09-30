import SwiftUI

/// Home's hourly-rate card for someone new: shown while there is no rate yet, or
/// before the first finished shift (so a new user can see and fix the rate they
/// typed in onboarding). With no rate it opens straight into the field; with one
/// it shows the rate and a Change button. Saves through `saveSettings`, the same
/// path as the Day Summary's rate row.
struct HomeRateCard: View {
    @ObservedObject var viewModel: AppViewModel
    let accent: Color

    @State private var isEditing = false
    @State private var rateText = ""
    @FocusState private var rateFocused: Bool

    private var rate: Double { viewModel.activeSettings.hourlyRate }

    var body: some View {
        Group {
            if rate > 0 && !isEditing {
                currentRow
            } else {
                editor
            }
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(radius: DS.Radius.md)
        .animation(DS.Motion.state, value: isEditing)
    }

    private var currentRow: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "banknote")
                .htFont(size: 17, relativeTo: .body, weight: .semibold)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(L10n.homeRateCurrent(PayFormatter.string(rate, currencyCode: viewModel.activeSettings.currencyCode)))
                .dsFont(.headline)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: DS.Space.xs)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                rateText = ""
                isEditing = true
                rateFocused = true
            } label: {
                Text(L10n.homeRateChange)
                    .dsFont(.meta, weight: .semibold)
                    .foregroundStyle(accent)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
                    .background(Capsule(style: .continuous).stroke(accent.opacity(0.55), lineWidth: 1.2))
            }
            .buttonStyle(ScalePressButtonStyle())
            .accessibilityIdentifier("home.rateChange")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(L10n.homeRateMissing)
                .dsFont(.headline)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.xs) {
                    Text(verbatim: currencySymbol)
                        .dsFont(.numLarge)
                        .foregroundStyle(DS.Palette.textSecondary)
                    // `AmountField`, not a plain TextField: those drew no digits in
                    // Hebrew/Arabic (see AI_AGENT_BRIEF, "Number Entry").
                    AmountField(
                        text: $rateText,
                        focus: $rateFocused,
                        size: 24,
                        textStyle: .title2,
                        weight: .semibold,
                        accent: accent,
                        accessibilityLabel: L10n.onbRateA11y,
                        identifier: "home.rateField"
                    )
                }
                .padding(.horizontal, DS.Space.md)
                .frame(minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Palette.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(rateBorder, lineWidth: rateText.isEmpty ? 1 : 1.5)
                )

                Button(action: save) {
                    Image(systemName: "checkmark")
                        .htFont(size: 17, relativeTo: .body, weight: .bold)
                        .foregroundStyle(DS.Palette.ink)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(accent.opacity(parsedRate == nil ? 0.35 : 1)))
                }
                .buttonStyle(.plain)
                .disabled(parsedRate == nil)
                .accessibilityLabel(L10n.sumRateSave)
                .accessibilityIdentifier("home.rateSave")
            }

            if !rateText.isEmpty, parsedRate == nil {
                Label(L10n.onbRateError, systemImage: "exclamationmark.circle")
                    .dsFont(.meta)
                    .foregroundStyle(DS.Palette.clockedIn)
            }
        }
    }

    private var parsedRate: Double? { OnboardingEstimate.parseRate(rateText) }

    private var rateBorder: Color {
        if rateText.isEmpty { return DS.Palette.hairline }
        return parsedRate == nil ? DS.Palette.clockedIn : DS.Palette.success
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = viewModel.activeSettings.currencyCode
        formatter.locale = AppLocale.resolvedLocale
        return formatter.currencySymbol ?? "₪"
    }

    private func save() {
        guard let value = parsedRate else { return }
        var settings = viewModel.activeSettings
        settings.hourlyRate = value
        viewModel.saveActiveWorkplaceSettings(settings)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        rateFocused = false
        isEditing = false
        rateText = ""
    }
}
