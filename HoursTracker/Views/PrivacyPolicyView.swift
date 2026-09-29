import SwiftUI

struct PrivacyPolicyView: View {
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    /// Fixed language (the consent screen's globe picker); `nil` = the app language.
    var language: AppLocale.Language?

    /// `privacy.section.<key>` / `privacy.body.<key>`, in reading order.
    static let sectionKeys = [
        "data",
        "account",
        "icloud",
        "ai",
        "support",
        "location",
        "camera",
        "tracking",
        "retention",
        "rights",
        "security",
        "controls",
        "children",
        "changes",
        "contact"
    ]

    private func t(_ key: String) -> String {
        language.map { AppLocale.localizedString(key, language: $0) } ?? AppLocale.tr(key)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(t("privacy.title"))
                    .font(.title2.weight(.bold))

                Text(t("privacy.updated"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(t("privacy.intro"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Self.sectionKeys, id: \.self) { key in
                    group(t("privacy.section.\(key)"), t("privacy.body.\(key)"))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("privacy.scroll")
        .background(appBackground.background.ignoresSafeArea())
        .navigationTitle(t("privacy.title"))
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
