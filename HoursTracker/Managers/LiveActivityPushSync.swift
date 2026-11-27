import ActivityKit
import Foundation
import UIKit
import os

/// Forwards this device's Live Activity push token and latest `ContentState`
/// to the backend (see `supabase/functions/live-activity-push`), so a 60s
/// server-side cron can keep re-delivering that exact state via APNs while
/// the app is fully suspended — SpringBoard then keeps recompositing the
/// Live Activity, and the client's own `Text(timerInterval:)` does the actual
/// visual ticking, same as a normal app-driven update. The server never
/// recomputes pay or elapsed time; it only ever re-sends what this encoder
/// already produced.
///
/// Complements `LiveActivityBackgroundRefresher` (a `BGAppRefreshTask`, which
/// iOS may or may not actually grant) rather than replacing it — this is the
/// guaranteed path, that one is the best-effort fallback if push delivery is
/// ever delayed or a token hasn't arrived yet.
@available(iOS 16.1, *)
enum LiveActivityPushSync {
    private static let functionURL = SupabaseConfig.projectURL.appendingPathComponent("functions/v1/live-activity-push")
    private static var tokenObservationTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.hourstracker.app", category: "live-activity-push")

    /// Starts watching this activity's push token. Tokens arrive asynchronously
    /// a short time after `Activity.request` — `push(state:)` calls before the
    /// first token lands are harmless no-ops.
    static func track(_ activity: Activity<HoursActivityAttributes>) {
        tokenObservationTask?.cancel()
        tokenObservationTask = Task {
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await send(action: "update", pushToken: token, state: nil)
            }
        }
    }

    /// Forwards the state just pushed to `activity.update()` so the server's
    /// cached copy never lags behind what's actually on screen. Call this
    /// from every `LiveActivityManager.start`/`update`.
    static func push(_ state: HoursActivityAttributes.ContentState) {
        Task { await send(action: "update", pushToken: nil, state: state) }
    }

    /// Call when the activity ends — stops the token observation and tells
    /// the server to stop re-delivering (clock-out, deleted shift, etc.).
    static func stop() {
        tokenObservationTask?.cancel()
        tokenObservationTask = nil
        Task { await send(action: "clear", pushToken: nil, state: nil) }
    }

    private static func send(action: String, pushToken: String?, state: HoursActivityAttributes.ContentState?) async {
        guard !(await AnnouncementCenter.isAutomatedRun) else { return }
        var body: [String: Any] = [
            "action": action,
            "deviceId": await AnnouncementCenter.shared.installID.uuidString,
        ]
        if let pushToken {
            body["pushToken"] = pushToken
            #if DEBUG
            body["apnsEnv"] = "sandbox"
            #else
            body["apnsEnv"] = "production"
            #endif
        }
        // Encoded with the plain default `JSONEncoder()` — no custom date
        // strategy — because that's the exact encoding ActivityKit's own push
        // delivery expects `content-state` to decode with on the device. Any
        // other encoding (e.g. ISO8601 strings) would silently fail to decode.
        if let state,
           let stateData = try? JSONEncoder().encode(state),
           let stateJSON = try? JSONSerialization.jsonObject(with: stateData) {
            body["contentState"] = stateJSON
        }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            logger.error("[\(action, privacy: .public)] failed to build request body")
            return
        }

        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody

        // The realistic way this gets exercised — clock in, glance at the Lock
        // Screen, lock the phone again — backgrounds the app moments after this
        // call starts. Without an explicit assertion, iOS can suspend the process
        // mid-flight and silently kill the request: no error, no completion, no
        // trace, which is exactly how this went undetected (server-side code was
        // fine the whole time; nothing was ever actually arriving). This buys the
        // ~30s iOS grants to let an in-flight request survive that.
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "live-activity-push") {
            logger.error("[\(action, privacy: .public)] background task expired before the request finished")
        }
        defer {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if !(200..<300).contains(status) {
                logger.error("[\(action, privacy: .public)] server rejected request: HTTP \(status, privacy: .public)")
            }
        } catch {
            logger.error("[\(action, privacy: .public)] request failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
