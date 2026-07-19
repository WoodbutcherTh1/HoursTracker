import Foundation
import os.log

/// Temporary diagnostic logger for Watch ↔ iPhone clock sync (Agent 7).
/// Filter Console with subsystem `com.hourstracker.app` category `WatchSync`.
public enum WatchSyncLog {
    public static let logger = Logger(subsystem: "com.hourstracker.app", category: "WatchSync")

    public static func event(_ message: String) {
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print("[WatchSync] \(message)")
        #endif
    }
}
