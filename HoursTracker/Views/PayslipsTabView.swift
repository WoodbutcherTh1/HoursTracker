import SwiftUI

/// Top-level "Payslips" tab — hosts `PayslipLibraryView` as its own navigation root
/// instead of being nested two taps deep inside Export. Owns its own `NavigationStack`
/// and its own `PayslipRecord` destination, since this stack no longer shares a path
/// with any other screen (unlike the old `ExportView`-hosted setup, where the library
/// and the export form had to register the same destination once at a shared root to
/// avoid SwiftUI silently failing to redraw on push — see the historical note that used
/// to live on `PayslipLibraryView`).
struct PayslipsTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    @StateObject private var payslipLibraryViewModel = PayslipLibraryViewModel()
    @State private var payslipDeleteError: String?

    var body: some View {
        NavigationStack {
            PayslipLibraryView(appViewModel: viewModel, viewModel: payslipLibraryViewModel)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        AssistantToolbarButton(onOpen: { viewModel.showAssistant = true })
                    }
                }
                .navigationDestination(for: PayslipRecord.self) { record in
                    PayslipDetailView(
                        record: record,
                        sourceURL: payslipLibraryViewModel.sourceURL(for: record),
                        onDelete: {
                            do {
                                try payslipLibraryViewModel.delete(record)
                                viewModel.showSuccessToast(L10n.payslipDeletedToast)
                                return true
                            } catch {
                                payslipDeleteError = error.localizedDescription
                                return false
                            }
                        }
                    )
                }
                .alert(L10n.payslipDeleteFailed, isPresented: Binding(
                    get: { payslipDeleteError != nil },
                    set: { if !$0 { payslipDeleteError = nil } }
                )) {
                    Button(L10n.editCancel, role: .cancel) { payslipDeleteError = nil }
                } message: {
                    Text(payslipDeleteError ?? "")
                }
        }
        .background(appBackground.background.ignoresSafeArea())
    }
}
