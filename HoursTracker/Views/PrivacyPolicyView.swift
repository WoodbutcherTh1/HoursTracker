import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.privacyTitle)
                    .font(.title2.weight(.bold))

                Text(L10n.privacyUpdated)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                group(L10n.privacySectionData, L10n.privacyBodyData)
                group(L10n.privacySectionLocation, L10n.privacyBodyLocation)
                group(L10n.privacySectionCamera, L10n.privacyBodyCamera)
                group(L10n.privacySectionTracking, L10n.privacyBodyTracking)
                group(L10n.privacySectionControls, L10n.privacyBodyControls)
                group(L10n.privacySectionContact, L10n.privacyBodyContact)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
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
