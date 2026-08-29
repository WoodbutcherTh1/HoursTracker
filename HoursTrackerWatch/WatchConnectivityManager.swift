import Foundation
import WatchConnectivity

/// Watch-side counterpart to the phone's `WatchConnectivityBridge`. Sends a
/// clock-in/out tap to the phone with `sendMessage` (live round trip, phone must be
/// reachable) and separately keeps a cached status from `didReceiveApplicationContext`
/// so the watch UI has something to show even when the phone isn't reachable right now.
///
/// NOT verified against a real build — written and reasoned through without Xcode or
/// a watchOS simulator available in this environment.
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var isClockedIn = false
    @Published private(set) var clockInDate: Date?
    @Published private(set) var isSending = false
    @Published var lastErrorMessage: String?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func toggleClock() {
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            lastErrorMessage = "Open HoursTracker on your iPhone first."
            return
        }
        isSending = true
        let action = isClockedIn ? "clockOut" : "clockIn"
        WCSession.default.sendMessage(["action": action], replyHandler: { [weak self] reply in
            Task { @MainActor in
                guard let self else { return }
                self.isSending = false
                if let stillIn = reply["isClockedIn"] as? Bool {
                    self.isClockedIn = stillIn
                    if !stillIn { self.clockInDate = nil }
                }
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.isSending = false
                self?.lastErrorMessage = error.localizedDescription
            }
        })
    }

    private func applyContext(_ context: [String: Any]) {
        if let isClockedIn = context["isClockedIn"] as? Bool {
            self.isClockedIn = isClockedIn
        }
        if let interval = context["clockInDate"] as? TimeInterval {
            clockInDate = Date(timeIntervalSince1970: interval)
        } else {
            clockInDate = nil
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let context = session.receivedApplicationContext as [String: Any]?, !context.isEmpty {
            Task { @MainActor in
                self.applyContext(context)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyContext(applicationContext)
        }
    }
}
