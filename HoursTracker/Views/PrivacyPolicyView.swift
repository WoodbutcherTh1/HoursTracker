import SwiftUI

struct PrivacyPolicyView: View {
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.privacyTitle)
                    .font(.title2.weight(.bold))

                Text(L10n.privacyUpdated)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(AppLocale.tr("privacy.intro"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                group(L10n.privacySectionData, L10n.privacyBodyData)
                group(AppLocale.tr("privacy.section.account"), AppLocale.tr("privacy.body.account"))
                group(L10n.privacySectionICloud, L10n.privacyBodyICloud)
                group(AppLocale.tr("privacy.section.ai"), AppLocale.tr("privacy.body.ai"))
                group(AppLocale.tr("privacy.section.support"), AppLocale.tr("privacy.body.support"))
                group(L10n.privacySectionLocation, L10n.privacyBodyLocation)
                group(L10n.privacySectionCamera, L10n.privacyBodyCamera)
                group(L10n.privacySectionTracking, L10n.privacyBodyTracking)
                group(AppLocale.tr("privacy.section.retention"), AppLocale.tr("privacy.body.retention"))
                group(AppLocale.tr("privacy.section.rights"), AppLocale.tr("privacy.body.rights"))
                group(AppLocale.tr("privacy.section.security"), AppLocale.tr("privacy.body.security"))
                group(L10n.privacySectionControls, L10n.privacyBodyControls)
                group(AppLocale.tr("privacy.section.children"), AppLocale.tr("privacy.body.children"))
                group(AppLocale.tr("privacy.section.changes"), AppLocale.tr("privacy.body.changes"))
                group(L10n.privacySectionContact, L10n.privacyBodyContact)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("privacy.scroll")
        .background(appBackground.background.ignoresSafeArea())
        .navigationTitle(L10n.privacyTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
