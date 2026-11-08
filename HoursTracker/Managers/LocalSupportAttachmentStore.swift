import UIKit

/// Where a support-chat photo attachment lives **before** there's a server to
/// send it to. Support chat (`SupportChatSheet`) currently has no attachment
/// upload channel — `SupportChatModel.send()` posts plain JSON text to the
/// `support-chat` edge function, nothing else.
///
// TODO: backend — add a Supabase Storage bucket + an upload field on the
// `support-chat` function, then have `SupportChatSheet` upload from here
// (or skip the local copy entirely) instead of only saving to disk. Until
// that exists, this keeps the picked photo on-device so the UI has
// something real to show/remove, without pretending it reached support.
enum LocalSupportAttachmentStore {
    private static var directory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SupportAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Saves a JPEG copy locally and returns its URL, or `nil` if encoding/writing failed.
    @discardableResult
    static func save(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
