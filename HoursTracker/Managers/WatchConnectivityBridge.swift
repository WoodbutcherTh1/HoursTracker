import Foundation
import WatchConnectivity

/// Phone-side half of the Apple Watch companion app. Two jobs: relay a clock-in/out
/// action tapped on the watch into the same `AppViewModel.clockIn()/clockOut()` path
/// the phone UI uses (no parallel state-mutation route), and push the current status
/// back to the watch via `updateApplicationContext` so it can show something useful
/// even when it hasn't been reachable for a live round trip.
///
/// NOT verified against a real build — written and reasoned through without Xcode or
/// a watchOS simulator available in this environment. Treat as a first draft to
/// compile and test on a real Mac, not as validated working code.
final class WatchConnectivityBridge: NSObject {
    private weak var viewModel: AppViewModel?

    func attach(to viewModel: AppViewModel) {
        self.viewModel = viewModel
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Call after every clock-in/out so the watch's cached status stays current even
    /// when it isn't reachable right now — `updateApplicationContext` delivers the
    /// latest value next time it wakes, superseding any earlier undelivered context.
    func pushStatus(isClockedIn: Bool, since: Date?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        var context: [String: Any] = ["isClockedIn": isClockedIn]
        if let since {
            context["clockInDate"] = since.timeIntervalSince1970
        }
        try? WCSession.default.updateApplicationContext(context)
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard let viewModel else { return }
        let isClockedIn = viewModel.isClockedIn
        let since = viewModel.activeSession?.clockIn
        pushStatus(isClockedIn: isClockedIn, since: since)
    }

    /// Live tap from the watch while both sides are reachable.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let action = message["action"] as? String else {
            replyHandler(["ok": false])
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else {
                replyHandler(["ok": false])
                return
            }
            switch action {
            case "clockIn":
                viewModel.clockIn()
            case "clockOut":
                viewModel.clockOut()
            default:
                replyHandler(["ok": false])
                return
            }
            self.pushStatus(isClockedIn: viewModel.isClockedIn, since: viewModel.activeSession?.clockIn)
            replyHandler(["ok": true, "isClockedIn": viewModel.isClockedIn])
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A new watch was paired — re-activate to start pairing with it.
        session.activate()
    }
}
