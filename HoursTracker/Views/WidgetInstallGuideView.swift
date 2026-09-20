import SwiftUI
import UIKit

/// Step-by-step "add the widget" guide shown from Settings. iOS offers no API
/// to install a widget programmatically (verified against the iOS 26 SDK), so
/// this is the fastest honest path: exact taps, whether one's already placed,
/// and a jump straight into the Home Screen edit mode's launchpad (Settings).
struct WidgetInstallGuideView: View {
    let installedCount: Int?
    @ObservedObject private var theme = HomeAccentTheme.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let installedCount {
                        Label(L10n.widgetGuideInstalled, systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.12)))
                    }

                    Text(L10n.widgetGuideIntro)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    guideStep(number: 1, text: L10n.widgetGuideStep1)
                    guideStep(number: 2, text: L10n.widgetGuideStep2)
                    guideStep(number: 3, text: L10n.widgetGuideStep3)

                    Button {
                        openHomeScreenSettings()
                    } label: {
                        Label(L10n.widgetGuideOpenSettings, systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .navigationTitle(L10n.widgetGuideTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.editCancel) { dismiss() }
                }
            }
        }
    }

    private func guideStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(theme.accent))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Best shortcut into edit mode: `App-Prefs` reaches iOS Settings, which on
    /// recent iOS lists Widgets under the app's own settings entry too. There
    /// is no public URL for the widget gallery itself.
    private func openHomeScreenSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
