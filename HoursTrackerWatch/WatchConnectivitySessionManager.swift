import Foundation
import HoursTrackerKit
import WatchConnectivity

/// Watch-side WatchConnectivity bridge + pending-actions flush.
@MainActor
final class WatchConnectivitySessionManager: NSObject, ObservableObject {
    static let shared = WatchConnectivitySessionManager()

    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var isPhoneReachable = false

    /// Shared App Group queue when available so a killed iPhone can drain on launch.
    let pendingQueue: WatchPendingActionQueue
    private var activated = false

    var onSnapshot: ((WatchSnapshot) -> Void)?

    private override init() {
        if let sharedURL = WatchSharedStore.pendingEventsURL {
            pendingQueue = WatchPendingActionQueue(fileURL: sharedURL)
        } else {
            pendingQueue = WatchPendingActionQueue()
        }
        super.init()
    }

    /// Seed UI from the local Documents cache before the phone answers.
    func applyCachedSnapshot(_ snap: WatchSnapshot) {
        snapshot = snap
    }

    /// DEBUG/manual-matrix only: treat the phone as unreachable so events stay queued.
    var forceUnreachable: Bool {
        ProcessInfo.processInfo.environment["HT_FORCE_WATCH_UNREACHABLE"] == "1"
            || ProcessInfo.processInfo.arguments.contains("HT_FORCE_WATCH_UNREACHABLE=1")
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if !activated {
            session.activate()
            activated = true
        }
    }

    /// Interactive or queued clock event — App Group file + durable WCSession.
    func sendClockEvent(_ event: WatchClockEvent) {
        // `pendingQueue` is backed by the App Group URL when available, so a killed
        // iPhone can drain the same file via `WidgetPendingEventStore` / `drainWidgetPendingEvents`.
        pendingQueue.enqueue(event)
        WatchSyncLog.event(
            "watch sendClockEvent \(event.kind.rawValue) id=\(event.id.uuidString.prefix(8)) reachable=\(isPhoneReachable)"
        )
        flushPending()
    }

    func requestSnapshot() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            let dict = try WatchWireCodec.dictionary(for: .requestSnapshot)
            deliver(dict, via: session, label: "requestSnapshot")
        } catch {}
    }

    func flushPending() {
        guard WCSession.isSupported() else { return }
        if forceUnreachable {
            WatchSyncLog.event("flushPending skipped (forceUnreachable) count=\(pendingQueue.pending.count)")
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            WatchSyncLog.event("flushPending skipped (not activated) count=\(pendingQueue.pending.count)")
            return
        }
        let pending = pendingQueue.snapshot()
        WatchSyncLog.event("flushPending count=\(pending.count) reachable=\(session.isReachable)")
        for event in pending {
            do {
                let dict = try WatchWireCodec.dictionary(for: .clockEvent(event))
                deliver(dict, via: session, label: "clockEvent:\(event.id.uuidString.prefix(8))")
            } catch {
                WatchSyncLog.event("flushPending encode failed id=\(event.id.uuidString.prefix(8))")
            }
        }
    }

    /// Always queue `transferUserInfo` (survives killed iPhone). Also `sendMessage` when reachable.
    private func deliver(_ dict: [String: Any], via session: WCSession, label: String) {
        // Durable path first — must not depend on isReachable / sendMessage success.
        session.transferUserInfo(dict)
        WatchSyncLog.event("transferUserInfo queued (\(label))")
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { error in
                WatchSyncLog.event("sendMessage failed (\(label)): \(error.localizedDescription)")
            }
            WatchSyncLog.event("sendMessage attempted (\(label))")
        }
    }

    private func handle(dictionary: [String: Any]) {
        guard let message = try? WatchWireCodec.message(from: dictionary) else { return }
        switch message {
        case .snapshot(let snap):
            snapshot = snap
            // Do not persist the raw phone snap here — `onSnapshot` merges pending first.
            onSnapshot?(snap)
        case .eventAck(let id):
            WatchSyncLog.event("watch ack received id=\(id.uuidString.prefix(8))")
            pendingQueue.remove(id: id)
            WidgetPendingEventStore.remove(id: id)
        case .clockEvent, .requestSnapshot:
            break
        }
    }
}

extension WatchConnectivitySessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            WatchSyncLog.event(
                "watch WCSession activation=\(activationState.rawValue) reachable=\(session.isReachable) err=\(String(describing: error))"
            )
            if let context = try? WatchWireCodec.message(from: session.receivedApplicationContext),
               case .snapshot(let snap) = context {
                self.snapshot = snap
                self.onSnapshot?(snap)
            }
            self.requestSnapshot()
            self.flushPending()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            WatchSyncLog.event("watch reachability → \(session.isReachable)")
            if session.isReachable {
                self.flushPending()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(dictionary: message) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            self.handle(dictionary: message)
            replyHandler([:])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.handle(dictionary: userInfo) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in self.handle(dictionary: applicationContext) }
    }
}
