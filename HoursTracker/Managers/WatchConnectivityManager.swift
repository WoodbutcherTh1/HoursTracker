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
///
/// ## Threading
/// `WCSession` IPC (`activate()`, `isPaired`, `isWatchAppInstalled`,
/// `updateApplicationContext(_:)`) is XPC to the paired-device daemon and can block
/// its caller for hundreds of milliseconds to multiple seconds. Running any of it on
/// the main thread shows up as a tab-switch hitch, so all of it is confined to
/// `bgQueue`. The flow on a state change is:
///   1. **bgQueue** — fast-exit guard (`isPaired`/`isWatchAppInstalled`). A phone with
///      no paired/installed Watch stops here and does *zero* main-thread work.
///   2. **main actor** — build the `WatchSnapshot` (reads `AppViewModel` state) and a
///      dedup digest.
///   3. **bgQueue** — drop the push if the semantic payload is unchanged, else send it.
/// `lastSyncedDigest`/`hasActivated` are only ever touched inside `bgQueue` (serial),
/// so they need no other synchronization; `viewModel`/`appLock`/`historyPeriodOffset`
/// are only ever touched on the main actor.
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    private weak var viewModel: AppViewModel?
    private weak var appLock: AppLockController?
    /// Payroll periods away from "now" the Watch's History tab is currently viewing.
    /// Purely view state for the Watch — not persisted, and not part of `AppViewModel`.
    /// Main-actor-confined (only read/written inside `@MainActor` work below).
    private var historyPeriodOffset = 0

    /// Dedicated serial background queue for all WCSession XPC — activation, state
    /// reads, and context updates. Serial so `lastSyncedDigest`/`hasActivated` stay
    /// race-free without extra locks.
    private let bgQueue = DispatchQueue(
        label: "com.hourstracker.wcsession.background",
        qos: .background
    )

    /// JSON of the last transmitted snapshot (with `generatedAt` normalized out) — lets
    /// us skip redundant `updateApplicationContext` calls when nothing semantic changed.
    /// `bgQueue`-confined.
    private var lastSyncedDigest: String?
    /// `bgQueue`-confined guard so repeated `configure(...)` calls (e.g. a view
    /// reappearing) don't re-activate the session.
    private var hasActivated = false

    private override init() {
        super.init()
    }

    func configure(viewModel: AppViewModel, appLock: AppLockController) {
        self.viewModel = viewModel
        self.appLock = appLock
        activateInBackground()
    }

    /// Activates `WCSession` entirely off the main thread. Safe to call more than once;
    /// only the first call activates.
    func activateInBackground() {
        bgQueue.async { [weak self] in
            guard let self, !self.hasActivated, WCSession.isSupported() else { return }
            self.hasActivated = true
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    /// Whether a Watch is currently paired and its session active. Reads WCSession on
    /// the background queue so callers (e.g. `AnnouncementCenter`) never touch Watch
    /// Connectivity IPC on the main actor. This is the single entry point for that
    /// check — all WCSession access on the phone goes through this manager's `bgQueue`.
    func isWatchPaired() async -> Bool {
        await withCheckedContinuation { continuation in
            bgQueue.async {
                let paired = WCSession.isSupported()
                    && WCSession.default.activationState == .activated
                    && WCSession.default.isPaired
                continuation.resume(returning: paired)
            }
        }
    }

    /// Pushes the current state to the Watch. Safe to call often — cheap when the
    /// session isn't activated/paired yet, and does no main-thread work at all unless a
    /// Watch app is actually paired and installed.
    func pushSnapshot() {
        bgQueue.async { [weak self] in
            guard let self, WCSession.isSupported() else { return }
            let session = WCSession.default
            // Fast-exit on the background queue. These reads are the XPC calls that
            // used to block the main thread; gating here means an unpaired phone never
            // even builds the snapshot on a state change.
            guard session.activationState == .activated,
                  session.isPaired,
                  session.isWatchAppInstalled else { return }
            self.buildAndSendSnapshot()
        }
    }

    /// Builds the snapshot on the main actor (it reads `AppViewModel`), then hands a
    /// plain `Data` payload + dedup digest back to `bgQueue` for the actual send.
    private func buildAndSendSnapshot() {
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else { return }
            let snapshot = viewModel.watchSnapshot(historyPeriodOffset: self.historyPeriodOffset)
            guard let payload = try? JSONEncoder().encode(snapshot) else { return }
            // `generatedAt` is a fresh timestamp on every call and would defeat dedup,
            // so it's zeroed for the digest only — the real payload keeps it.
            var digestSource = snapshot
            digestSource.generatedAt = .distantPast
            let digest = (try? JSONEncoder().encode(digestSource))
                .map { String(decoding: $0, as: UTF8.self) }
            self.deliver(snapshotData: payload, digest: digest)
        }
    }

    /// Sends the encoded snapshot over `updateApplicationContext`, skipping the XPC call
    /// when the semantic payload is identical to the last one we sent. Reconstructs the
    /// exact message `WatchSnapshot.asMessage()` produces — only `Data`/`String` (both
    /// Sendable) cross the queue boundary.
    private func deliver(snapshotData: Data, digest: String?) {
        bgQueue.async { [weak self] in
            guard let self else { return }
            let session = WCSession.default
            // State can change between the entry guard and here (e.g. Watch app removed
            // mid-session), so re-check before touching IPC.
            guard session.activationState == .activated,
                  session.isPaired,
                  session.isWatchAppInstalled else { return }
            if let digest, digest == self.lastSyncedDigest { return }
            do {
                try session.updateApplicationContext([WatchMessageKey.snapshot: snapshotData])
                self.lastSyncedDigest = digest
            } catch {
                // Non-fatal background sync failure; leave `lastSyncedDigest` untouched
                // so the next genuinely-new state still attempts a push.
            }
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

    /// Pairing/installation changed (Watch app installed or removed, device paired or
    /// unpaired). Clear the dedup cache so the next eligible push isn't suppressed, then
    /// re-push the current state.
    func sessionWatchStateDidChange(_ session: WCSession) {
        bgQueue.async { [weak self] in self?.lastSyncedDigest = nil }
        pushSnapshot()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        bgQueue.async { session.activate() }
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
            case .startBreak:
                viewModel.startBreak()
            case .endBreak:
                viewModel.endBreak()
            case .shiftHistoryPeriod:
                self.historyPeriodOffset += request.intValue ?? 0
            case .toggleAppLock:
                self.appLock?.isEnabled = request.boolValue ?? false
            case .toggleHideWidgetPay:
                WidgetBridge.hidePay = request.boolValue ?? false
                // Reload after the (now off-main) hidePay suite write — see WidgetBridge.ioAsync.
                WidgetBridge.ioAsync { WidgetBridge.reloadWidgetTimelines() }
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
    /// `WatchExportView` only ever sends these two literal keys. Matching them
    /// by name (not falling through an implicit `default:` for "whatever isn't
    /// thisYear") means a request this doesn't recognize is a visible, reported
    /// error instead of silently resolving to a range the user didn't ask for.
    private enum WatchExportRangeKey: String {
        case thisMonth
        case thisYear
    }

    @MainActor
    private func handleExportRequest(
        _ rangeKey: String?,
        viewModel: AppViewModel,
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let rangeKey, let key = WatchExportRangeKey(rawValue: rangeKey) else {
            replyHandler(WatchAck(success: false, message: L10n.errorTitle).asMessage())
            return
        }
        let calendar = Calendar.current
        let range: ExportDateRange
        switch key {
        case .thisYear:
            range = .year(calendar.component(.year, from: Date()))
        case .thisMonth:
            // Same payroll-period math the phone's own Export tab uses for its
            // "This Month" — a payroll period, not necessarily a calendar month.
            let period = HistoryPeriodHelper.payrollPeriod(containing: Date(), startDay: viewModel.activeSettings.payrollStartDay)
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
