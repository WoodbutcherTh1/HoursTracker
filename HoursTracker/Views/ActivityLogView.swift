import SwiftUI

struct ActivityLogView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var store = ActivityLogStore.shared
    @State private var selectedFormat: ActivityLogExportFormat = .txt
    @State private var shareItem: ShareableFile?
    @State private var showClearConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker(L10n.logExportFormat, selection: $selectedFormat) {
                    ForEach(ActivityLogExportFormat.allCases) { format in
                        Text(format.localizedName).tag(format)
                    }
                }

                Button {
                    exportLog()
                } label: {
                    Label(L10n.logExport, systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label(L10n.logClear, systemImage: "trash")
                }
            } header: {
                Text(L10n.logActions)
            } footer: {
                Text(L10n.logExportHint)
            }

            Section(L10n.logEntries) {
                if store.entries.isEmpty {
                    Text(L10n.logEmpty)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.category.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(color(for: entry.level))
                                Spacer()
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.subheadline)
                            if let details = entry.details, !details.isEmpty {
                                Text(details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.timestamp, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(L10n.logTitle)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L10n.logClearConfirm, isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(L10n.logClear, role: .destructive) {
                store.clear()
                viewModel.showSuccessToast(L10n.feedbackLogCleared)
            }
            Button(L10n.editCancel, role: .cancel) {}
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(L10n.errorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.errorOK, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func exportLog() {
        do {
            let url = try store.export(format: selectedFormat)
            DispatchQueue.main.async {
                shareItem = ShareableFile(url: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func color(for level: ActivityLogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
