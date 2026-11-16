import SwiftUI

/// Settings → Inbox: the persistent history of owner announcements (seen and
/// unseen), unlike `AnnouncementCenterOverlay` which only ever shows one
/// unseen message at a time and then forgets it. Opening this screen marks
/// everything currently unread as read, same as a normal mail inbox.
struct UserInboxView: View {
    @ObservedObject private var center = AnnouncementCenter.shared
    @State private var items: [AnnouncementHistoryItem] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if items.isEmpty && !isLoading {
                Text(L10n.inboxEmpty)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if !item.seen {
                            Circle()
                                .fill(Color.appAccent)
                                .frame(width: 8, height: 8)
                        }
                        Text(item.title)
                            .font(.body.weight(item.seen ? .regular : .semibold))
                        Spacer()
                        if let date = item.createdAt {
                            Text(date, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(item.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle(L10n.inboxTitle)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await center.fetchHistory()
        let unseenIDs = items.filter { !$0.seen }.map(\.id)
        guard !unseenIDs.isEmpty else { return }
        await center.acknowledge(unseenIDs)
        for index in items.indices where !items[index].seen {
            items[index].seen = true
        }
    }
}

#Preview {
    NavigationStack { UserInboxView() }
}
