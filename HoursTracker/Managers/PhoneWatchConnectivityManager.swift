import Foundation
import HoursTrackerKit
import WatchConnectivity

/// iOS-side WatchConnectivity bridge. Pushes snapshots; receives clock events.
@MainActor
final class PhoneWatchConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneWatchConnectivityManager()

    @Published private(set) var isWatchReachable = false

    /// Called when the watch delivers a clock event that the phone should apply.
    var onClockEvent: ((WatchClockEvent) -> Void)?
    /// Build the latest snapshot to send (sessions + trimmed pay settings).
    var snapshotProvider: (() -> WatchSnapshot)?

    private var activated = false

    private override init() {
        super.init()
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

    func pushSnapshot(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            let dict = try WatchWireCodec.dictionary(for: .snapshot(snapshot))
            // applicationContext may error if payload equals the last one — still
            // deliver via transferUserInfo/sendMessage so a newly-reachable watch
            // gets the current snapshot even when sessions did not change.
            do {
                try session.updateApplicationContext(dict)
            } catch {
                // Identical-context errors are expected on reachability re-push.
            }
            if session.isReachable {
                session.sendMessage(dict, replyHandler: nil) { _ in
                    session.transferUserInfo(dict)
                }
            } else {
                session.transferUserInfo(dict)
            }
        } catch {
            // Best-effort; phone remains source of truth locally.
        }
    }

    func acknowledge(eventID: UUID) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            let dict = try WatchWireCodec.dictionary(for: .eventAck(eventID))
            if session.isReachable {
                session.sendMessage(dict, replyHandler: nil) { _ in
                    session.transferUserInfo(dict)
                }
            } else {
                session.transferUserInfo(dict)
            }
        } catch {}
    }

    private func handle(dictionary: [String: Any]) {
        guard let message = try? WatchWireCodec.message(from: dictionary) else { return }
        switch message {
        case .clockEvent(let event):
            onClockEvent?(event)
        case .requestSnapshot:
            if let snapshot = snapshotProvider?() {
                pushSnapshot(snapshot)
            }
        case .snapshot, .eventAck:
            break
        }
    }
}

extension PhoneWatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
            if let snapshot = self.snapshotProvider?() {
                self.pushSnapshot(snapshot)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
            // Watch may have missed applicationContext while unreachable — push
            // the latest snapshot whenever it becomes reachable again (even if
            // sessions/settings did not change).
            if session.isReachable, let snapshot = self.snapshotProvider?() {
                self.pushSnapshot(snapshot)
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
