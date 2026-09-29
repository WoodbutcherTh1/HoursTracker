import SwiftUI

/// In-app Terms of Use — the only copy (like the privacy policy), shown from the
/// consent screen and from Settings → About.
struct TermsOfUseView: View {
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    struct Part: Identifiable {
        let titleKey: String
        let bodyKey: String
        var id: String { titleKey }
    }

    /// Catalog keys, in reading order.
    static let sections: [Part] = [
        Part(titleKey: "terms.section.service", bodyKey: "terms.body.service"),
        Part(titleKey: "terms.section.estimates", bodyKey: "terms.body.estimates"),
        Part(titleKey: "terms.section.responsibility", bodyKey: "terms.body.responsibility"),
        Part(titleKey: "terms.section.account", bodyKey: "terms.body.account"),
        Part(titleKey: "terms.section.ai", bodyKey: "terms.body.ai"),
        Part(titleKey: "terms.section.use", bodyKey: "terms.body.use"),
        Part(titleKey: "terms.section.liability", bodyKey: "terms.body.liability"),
        Part(titleKey: "terms.section.changes", bodyKey: "terms.body.changes"),
        Part(titleKey: "terms.section.law", bodyKey: "terms.body.law"),
        Part(titleKey: "terms.section.contact", bodyKey: "terms.body.contact")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocale.tr("terms.title"))
                    .font(.title2.weight(.bold))

                Text(L10n.privacyUpdated)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(AppLocale.tr("terms.intro"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Self.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocale.tr(section.titleKey))
                            .font(.headline)
                        Text(AppLocale.tr(section.bodyKey))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("terms.scroll")
        .background(appBackground.background.ignoresSafeArea())
        .navigationTitle(AppLocale.tr("terms.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
