import Foundation
import WatchConnectivity

/// Bridges the phone's full app state to the paired Watch app. The phone is the sole
/// source of truth: it pushes a fresh `WatchSnapshot` via `updateApplicationContext`
/// after every state change (mirrors the existing `WidgetBridge` push-on-change
/// pattern), and answers every `WatchRequest` the Watch sends with `sendMessage` —
/// clock in/out, paging through History periods, Settings toggles, and export
/// requests — replying with the resulting snapshot so the Watch UI updates instantly
/// even before the next context push arrives.
///
/// Not `@MainActor` itself (`WCSessionDelegate` callbacks land on an arbitrary
/// background queue) — every touch of `AppViewModel` hops to the main actor
/// explicitly instead.
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    private weak var viewModel: AppViewModel?
    private weak var appLock: AppLockController?
    /// Payroll periods away from "now" the Watch's History tab is currently viewing.
    /// Purely view state for the Watch — not persisted, and not part of `AppViewModel`.
    private var historyPeriodOffset = 0

    private override init() {
        super.init()
    }

    func configure(viewModel: AppViewModel, appLock: AppLockController) {
        self.viewModel = viewModel
        self.appLock = appLock
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Pushes the current state to the Watch. Safe to call often — cheap when
    /// the session isn't activated/paired yet (no-ops rather than erroring).
    func pushSnapshot() {
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else { return }
            let snapshot = viewModel.watchSnapshot(historyPeriodOffset: self.historyPeriodOffset)
            guard WCSession.isSupported() else { return }
            let session = WCSession.default
            guard session.activationState == .activated else { return }
            try? session.updateApplicationContext(snapshot.asMessage())
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        pushSnapshot()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Every request the Watch sends — clock in/out, History paging, Settings
    /// toggles, export requests. The phone applies each one through the same paths
    /// the phone UI itself uses (persistence, Live Activity, sync — all unchanged),
    /// then replies with a fresh snapshot so the Watch doesn't have to wait for a
    /// separate context push.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let request = WatchRequest.from(message: message) else {
            replyHandler(WatchAck(success: false, message: "unknown_request").asMessage())
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else {
                replyHandler(WatchAck(success: false, message: "not_ready").asMessage())
                return
            }

            switch request.kind {
            case .clockIn:
                viewModel.clockIn()
            case .clockOut:
                viewModel.clockOut()
            case .shiftHistoryPeriod:
                self.historyPeriodOffset += request.intValue ?? 0
            case .toggleAppLock:
                self.appLock?.isEnabled = request.boolValue ?? false
            case .toggleHideWidgetPay:
                WidgetBridge.hidePay = request.boolValue ?? false
                WidgetBridge.reloadWidgetTimelines()
            case .toggleCloudSync:
                let enabled = request.boolValue ?? false
                if enabled {
                    viewModel.isICloudSyncEnabled = true
                } else {
                    viewModel.disableICloudSync(deleteRemoteData: false)
                }
            case .setLanguage:
                if let raw = request.stringValue, let option = AppLanguageOption(rawValue: raw) {
                    AppLanguageController.shared.preference = option
                }
            case .requestExport:
                self.handleExportRequest(request.stringValue, viewModel: viewModel, replyHandler: replyHandler)
                return
            case .requestFullSnapshot:
                break
            }

            let snapshot = viewModel.watchSnapshot(historyPeriodOffset: self.historyPeriodOffset)
            replyHandler(snapshot.asMessage())
            self.pushSnapshot()
        }
    }

    /// Generates the requested export with the same pipeline the Export tab's own
    /// button uses, then hands the file to `AppViewModel.pendingWatchExport` so the
    /// phone presents its native share sheet the next time Export is open — the
    /// Watch cannot present `UIActivityViewController` itself.
    @MainActor
    private func handleExportRequest(
        _ rangeKey: String?,
        viewModel: AppViewModel,
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let calendar = Calendar.current
        let range: ExportDateRange
        switch rangeKey {
        case "thisYear":
            range = .year(calendar.component(.year, from: Date()))
        default:
            let period = HistoryPeriodHelper.payrollPeriod(containing: Date(), startDay: viewModel.settings.payrollStartDay)
            range = .custom(from: period.start, to: period.end)
        }
        do {
            let url = try viewModel.export(range: range, format: .pdf, language: .phone)
            viewModel.pendingWatchExport = ShareableFile(url: url)
            replyHandler(WatchAck(success: true, message: nil).asMessage())
        } catch {
            replyHandler(WatchAck(success: false, message: error.localizedDescription).asMessage())
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Phone never receives application context — only the Watch does.
    }
}
