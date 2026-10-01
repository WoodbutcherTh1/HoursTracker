import SwiftUI

/// Settings → Data safety → Recently deleted: every shift deleted in the last 30
/// days, restorable with one tap.
struct RecentlyDeletedView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var items: [DeletedSession] = []

    var body: some View {
        List {
            if items.isEmpty {
                Text(L10n.dataSafetyRecentlyDeletedEmpty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.shiftFormatter.string(from: item.session.clockIn))
                            .font(.subheadline.weight(.semibold))
                        Text(shiftRange(item.session))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.dataSafetyDeletedOn(Self.deletedFormatter.string(from: item.deletedAt)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.deleteForever(id: item.id)
                            reload()
                        } label: {
                            Label(L10n.dataSafetyDeleteForever, systemImage: "trash.slash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            restore(item)
                        } label: {
                            Label(L10n.dataSafetyRestore, systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                    .contextMenu {
                        Button {
                            restore(item)
                        } label: {
                            Label(L10n.dataSafetyRestore, systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.dataSafetyRecentlyDeleted)
        .onAppear(perform: reload)
    }

    private func restore(_ item: DeletedSession) {
        viewModel.restoreDeletedSession(id: item.id)
        viewModel.showSuccessToast(L10n.dataSafetyRestored)
        reload()
    }

    private func reload() {
        items = viewModel.recentlyDeletedSessions
    }

    private func shiftRange(_ session: WorkSession) -> String {
        let time = AppLocale.makeDateFormatter(timeStyle: .short)
        let start = time.string(from: session.clockIn)
        guard let end = session.clockOut else { return start }
        return "\(start) – \(time.string(from: end))"
    }

    private static var shiftFormatter: DateFormatter {
        AppLocale.makeDateFormatter(dateStyle: .full)
    }

    private static var deletedFormatter: DateFormatter {
        AppLocale.makeDateFormatter(dateStyle: .medium, timeStyle: .short)
    }
}

/// Settings → Data safety → Automatic backups: the daily on-device backups (kept
/// 14 days), each restorable after a confirmation.
struct LocalBackupsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var backups: [LocalBackup] = []
    @State private var pendingRestore: LocalBackup?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if backups.isEmpty {
                Text(L10n.dataSafetyBackupsEmpty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(backups) { backup in
                    Button {
                        pendingRestore = backup
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Self.formatter.string(from: backup.createdAt))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(backup.isPreRestore
                                     ? "\(L10n.dataSafetyBackupsPreRestore) · \(L10n.dataSafetyBackupsShifts(backup.sessionCount))"
                                     : L10n.dataSafetyBackupsShifts(backup.sessionCount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.dataSafetyBackups)
        .onAppear { backups = viewModel.localBackups }
        .confirmationDialog(
            L10n.dataSafetyBackupsConfirmTitle,
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.dataSafetyRestore, role: .destructive) {
                guard let backup = pendingRestore else { return }
                do {
                    try viewModel.restoreBackup(backup)
                    viewModel.showSuccessToast(L10n.dataSafetyRestored)
                    backups = viewModel.localBackups
                } catch {
                    errorMessage = error.localizedDescription
                }
                pendingRestore = nil
            }
            Button(L10n.editCancel, role: .cancel) { pendingRestore = nil }
        } message: {
            Text(L10n.dataSafetyBackupsConfirmMessage)
        }
        .alert(
            L10n.errorTitle,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(L10n.errorOK, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private static var formatter: DateFormatter {
        AppLocale.makeDateFormatter(dateStyle: .full, timeStyle: .short)
    }
}
