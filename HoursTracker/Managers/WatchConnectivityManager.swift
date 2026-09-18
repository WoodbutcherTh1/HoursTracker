import Foundation
import WatchConnectivity

/// Bridges clock/pay state to the paired Watch app. The phone is the source of
/// truth: it pushes a fresh `WatchSnapshot` via `updateApplicationContext` after
/// every state change (mirrors the existing `WidgetBridge` push-on-change pattern),
/// and answers `.clockIn`/`.clockOut` requests the Watch sends with `sendMessage`,
/// replying with the resulting snapshot so the Watch UI updates instantly even
/// before the next context push arrives.
///
/// Not `@MainActor` itself (WCSessionDelegate callbacks land on an arbitrary
/// background queue) — every touch of `AppViewModel` hops to the main actor
/// explicitly instead.
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    private weak var viewModel: AppViewModel?

    private override init() {
        super.init()
    }

    func configure(viewModel: AppViewModel) {
        self.viewModel = viewModel
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Pushes the current state to the Watch. Safe to call often — cheap when
    /// the session isn't activated/paired yet (no-ops rather than erroring).
    func pushSnapshot() {
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else { return }
            let snapshot = viewModel.watchSnapshot
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

    /// The Watch requesting a clock in/out. The phone applies it through the same
    /// `AppViewModel.clockIn()/clockOut()` path the UI uses (persistence, Live
    /// Activity, reminders, sync — all unchanged), then replies with the fresh
    /// snapshot so the Watch doesn't have to wait for a separate context push.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard
            let raw = message[WatchMessageKey.action] as? String,
            let action = WatchAction(rawValue: raw)
        else {
            replyHandler(["error": "unknown_action"])
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else {
                replyHandler(["error": "not_ready"])
                return
            }
            switch action {
            case .clockIn: viewModel.clockIn()
            case .clockOut: viewModel.clockOut()
            }
            replyHandler(viewModel.watchSnapshot.asMessage())
            self.pushSnapshot()
        }
    }
}
