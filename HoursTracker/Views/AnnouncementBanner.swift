import SwiftUI

/// In-app copy of an owner announcement, shown once at the top of the app until
/// the user taps "Got it" (see `AnnouncementCenter`).
struct AnnouncementBanner: View {
    let announcement: Announcement
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.announcementHeader, systemImage: "megaphone.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !announcement.title.isEmpty {
                Text(verbatim: announcement.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            ScrollView {
                Text(verbatim: announcement.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text(L10n.announcementDismiss)
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}
