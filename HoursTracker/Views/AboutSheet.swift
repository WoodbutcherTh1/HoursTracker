import SwiftUI

/// Opened from the brand mark on Home. Also where the wordmark — custom or not —
/// still shows now that Home's toolbar no longer carries it.
struct AboutSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showContactSupport = false

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: DS.Space.sm) {
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(theme.accent.opacity(0.15))
                            .overlay(
                                Image(systemName: "hourglass.bottomhalf.filled")
                                    .symbolRenderingMode(.hierarchical)
                                    .htFont(size: 30, relativeTo: .largeTitle, weight: .semibold)
                                    .foregroundStyle(theme.accent)
                            )
                            .frame(width: 64, height: 64)
                            .accessibilityHidden(true)
                        HomeBrandTitle(accent: theme.accent)
                        Text(verbatim: versionString)
                            .dsFont(.meta)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .environment(\.layoutDirection, .leftToRight)
                            .accessibilityLabel("\(L10n.settingsVersion) \(versionString)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.md)
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label(L10n.privacyTitle, systemImage: "hand.raised.fill")
                    }
                    Button {
                        showContactSupport = true
                    } label: {
                        Label(L10n.settingsSupport, systemImage: "envelope")
                    }
                    if let rateURL = URL(string: "https://apps.apple.com/app/id6790862413?action=write-review") {
                        Link(destination: rateURL) {
                            Label(L10n.settingsRateApp, systemImage: "star.fill")
                        }
                    }
                }
                .listRowBackground(DS.Palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(appBackground.background.ignoresSafeArea())
            .navigationTitle(L10n.settingsAbout)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.summaryDone) { dismiss() }
                }
            }
            .tint(theme.accent)
            .sheet(isPresented: $showContactSupport) {
                ContactSupportSheet(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
    }
}
