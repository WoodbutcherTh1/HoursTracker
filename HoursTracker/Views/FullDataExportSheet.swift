import SwiftUI

/// Settings sheet: pick a full-export format, build the file, then share.
struct FullDataExportSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: FullDataExportFormat = .pdf
    @State private var isExporting = false
    @State private var shareItem: ShareableFile?
    @State private var errorMessage: String?

    private let exporter = FullDataExportManager()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(FullDataExportFormat.allCases) { format in
                        Button {
                            selectedFormat = format
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selectedFormat == format ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedFormat == format ? Color.accentColor : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(format.localizedName)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(format.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(L10n.fullExportChooseFormat)
                } footer: {
                    Text(L10n.fullExportFooter)
                }

                Section {
                    Button {
                        runExport()
                    } label: {
                        if isExporting {
                            HStack {
                                ProgressView()
                                Text(L10n.fullExportPreparing)
                            }
                        } else {
                            Label(L10n.fullExportAction, systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle(L10n.fullExportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.editCancel) { dismiss() }
                }
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
            .sheet(item: $shareItem, onDismiss: {
                viewModel.showSuccessToast(L10n.fullExportSuccess)
                dismiss()
            }) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    private func runExport() {
        errorMessage = nil
        isExporting = true

        do {
            let url = try exporter.export(
                settings: viewModel.settings,
                sessions: viewModel.sessions,
                activityLog: ActivityLogStore.shared.entries,
                format: selectedFormat,
                language: .phone
            )
            ActivityLogStore.shared.log(
                L10n.logEventFullDataExport,
                level: .success,
                category: "export",
                details: selectedFormat.rawValue
            )
            // Nested sheet: wait one turn so SwiftUI has a stable presenter
            // and `.sheet(item:)` always receives a non-nil value.
            DispatchQueue.main.async {
                isExporting = false
                shareItem = ShareableFile(url: url)
            }
        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
        }
    }
}
