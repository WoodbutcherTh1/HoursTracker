import SwiftUI
import UniformTypeIdentifiers

/// Settings → Backup: export, import, Sync Now, last-backup indicator.
struct BackupSettingsSection: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var isWorking = false
    @State private var shareItem: ShareableFile?
    @State private var errorMessage: String?
    @State private var showImporter = false
    @State private var pendingDocument: FullBackupDocument?
    @State private var showRestoreConfirm = false

    private var stampFormatter: DateFormatter {
        AppLocale.makeDateFormatter(dateStyle: .medium, timeStyle: .short)
    }

    var body: some View {
        Section {
            lastBackupRow

            Button {
                runExport()
            } label: {
                Label(
                    isWorking ? L10n.backupPreparing : L10n.backupExport,
                    systemImage: "square.and.arrow.up.on.square"
                )
            }
            .disabled(isWorking)
            .accessibilityIdentifier("phone.settings.backup.export")

            Button {
                runSyncNow()
            } label: {
                Label(L10n.backupSyncNow, systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isWorking)
            .accessibilityIdentifier("phone.settings.backup.sync")

            Button {
                showImporter = true
            } label: {
                Label(L10n.backupImport, systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(isWorking)
            .accessibilityIdentifier("phone.settings.backup.import")
        } header: {
            Text(L10n.backupSection)
        } footer: {
            Text(L10n.backupExportHint)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url]) {
                viewModel.showSuccessToast(L10n.backupExportSuccess)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.importTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .confirmationDialog(
            L10n.backupConfirmTitle,
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.backupReplace, role: .destructive) {
                applyRestore(mode: .replace)
            }
            Button(L10n.backupMerge) {
                applyRestore(mode: .merge)
            }
            Button(L10n.editCancel, role: .cancel) {
                pendingDocument = nil
            }
        } message: {
            Text(restoreSummaryText)
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

    private var lastBackupRow: some View {
        Group {
            if let date = viewModel.lastBackupDate {
                Label(
                    L10n.backupLast(stampFormatter.string(from: date)),
                    systemImage: "clock.badge.checkmark"
                )
                .foregroundStyle(.primary)
                .accessibilityIdentifier("phone.settings.backup.last")
            } else {
                Label(L10n.backupLastNone, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("phone.settings.backup.lastNone")
            }
        }
        // Refresh when backups run.
        .id(viewModel.lastBackupDate?.timeIntervalSince1970 ?? 0)
    }

    private var restoreSummaryText: String {
        guard let doc = pendingDocument else { return "" }
        let summary = FullBackupManager.shared.summary(of: doc)
        var lines = [
            L10n.backupSummarySessions(summary.sessionCount),
            L10n.backupSummaryMonths(summary.monthCount)
        ]
        if let last = summary.lastSessionClockIn {
            lines.append(L10n.backupSummaryLastShift(stampFormatter.string(from: last)))
        }
        if !summary.workerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(summary.workerName)
        }
        return lines.joined(separator: "\n")
    }

    private func runExport() {
        errorMessage = nil
        isWorking = true
        do {
            let url = try viewModel.exportFullBackupFile()
            ActivityLogStore.shared.log(
                L10n.logEventBackupExported,
                level: .success,
                category: "backup",
                details: "share"
            )
            DispatchQueue.main.async {
                isWorking = false
                shareItem = ShareableFile(url: url)
            }
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }

    private func runSyncNow() {
        errorMessage = nil
        isWorking = true
        do {
            try viewModel.syncFullBackupNow()
            ActivityLogStore.shared.log(
                L10n.logEventBackupExported,
                level: .success,
                category: "backup",
                details: "syncNow"
            )
            isWorking = false
            viewModel.showSuccessToast(L10n.backupSyncSuccess)
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let document = try viewModel.loadBackupDocument(from: url)
                pendingDocument = document
                showRestoreConfirm = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyRestore(mode: FullBackupRestoreMode) {
        guard let document = pendingDocument else { return }
        pendingDocument = nil
        do {
            try viewModel.restoreBackup(document, mode: mode)
            viewModel.showSuccessToast(L10n.backupRestoreSuccess)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static var importTypes: [UTType] {
        var types: [UTType] = [.json]
        if let custom = UTType(filenameExtension: "htbackup.json") {
            types.insert(custom, at: 0)
        }
        // Also allow generic .json and double-extension via public data.
        types.append(.data)
        return types
    }
}
