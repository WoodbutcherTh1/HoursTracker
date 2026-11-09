import SwiftUI

/// Top-level "Payslips" tab (B7) — hosts `PayslipLibraryView` as its own
/// navigation root instead of two taps deep inside Export. Owns the
/// `PayslipRecord` destination at its stack root (declared once, so SwiftUI
/// never has two copies competing — see `PayslipLibraryView`).
struct PayslipsTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    @StateObject private var payslipLibraryViewModel = PayslipLibraryViewModel()
    @State private var payslipDeleteError: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
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
        // "Comes back closed" — same intent as the removed tab-level `.id()` reset
        // in MainTabView: pop any pushed PayslipDetailView, but without destroying
        // `payslipLibraryViewModel` (no reason to re-fetch the library every switch).
        .onDisappear { path = NavigationPath() }
        .background(appBackground.background.ignoresSafeArea())
    }
}
