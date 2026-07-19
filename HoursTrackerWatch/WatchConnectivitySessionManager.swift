import Foundation
import HoursTrackerKit
import WatchConnectivity

/// Watch-side WatchConnectivity bridge + pending-actions flush.
@MainActor
final class WatchConnectivitySessionManager: NSObject, ObservableObject {
    static let shared = WatchConnectivitySessionManager()

    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var isPhoneReachable = false

    let pendingQueue = WatchPendingActionQueue()
    private var activated = false

    var onSnapshot: ((WatchSnapshot) -> Void)?

    private override init() {
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

    /// Interactive or queued clock event.
    func sendClockEvent(_ event: WatchClockEvent) {
        pendingQueue.enqueue(event)
        flushPending()
    }

    func requestSnapshot() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            let dict = try WatchWireCodec.dictionary(for: .requestSnapshot)
            if session.isReachable {
                session.sendMessage(dict, replyHandler: nil) { _ in
                    session.transferUserInfo(dict)
                }
            } else {
                session.transferUserInfo(dict)
            }
        } catch {}
    }

    func flushPending() {
        guard WCSession.isSupported() else { return }
        if forceUnreachable { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        for event in pendingQueue.snapshot() {
            do {
                let dict = try WatchWireCodec.dictionary(for: .clockEvent(event))
                if session.isReachable {
                    session.sendMessage(dict, replyHandler: nil) { _ in
                        session.transferUserInfo(dict)
                    }
                } else {
                    session.transferUserInfo(dict)
                }
            } catch {}
        }
    }

    private func handle(dictionary: [String: Any]) {
        guard let message = try? WatchWireCodec.message(from: dictionary) else { return }
        switch message {
        case .snapshot(let snap):
            snapshot = snap
            WatchPersistenceManager.shared.save(snap)
            onSnapshot?(snap)
        case .eventAck(let id):
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
