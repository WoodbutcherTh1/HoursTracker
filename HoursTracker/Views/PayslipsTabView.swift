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
        //
        // Deferred one run-loop tick (plain `.async`, no delay — NOT a timed sleep,
        // which would just move the race to wherever the delay runs out instead of
        // removing it): mutating `path` synchronously inside `onDisappear` lands in
        // the SAME SwiftUI transaction as TabView's own tab-switch update, and two
        // navigation-identity changes in one transaction is exactly what produced
        // "NavigationRequestObserver tried to update multiple times per frame" and
        // the follow-on freeze. Dispatching to the next tick lets that transaction
        // finish committing first. `disablesAnimations` on top of that: without it,
        // this reset can still inherit whatever animation was active on the tick it
        // lands on and get merged into the TabView's own transition, which is the
        // same double-update the dispatch is trying to avoid.
        .onDisappear {
            DispatchQueue.main.async {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { path = NavigationPath() }
            }
        }
        .background(appBackground.background.ignoresSafeArea())
    }
}
