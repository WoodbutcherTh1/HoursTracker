import Foundation

/// Shared dirty bit for rolling auto-backup (Chunk 2 / PR #37).
/// Uses the same UserDefaults key as `FullBackupManager` so payslip mutations on
/// this branch still trigger auto-backup once the backup stack is merged.
enum BackupContentDirtyFlag {
    static let key = "ht.backup.contentDirty"

    static func mark() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func isDirty() -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
