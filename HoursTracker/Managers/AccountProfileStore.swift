import Foundation
import UIKit

/// Stores the account's profile picture locally (Facebook-style: blank
/// initials avatar until the user picks one). The image is downscaled and
/// re-encoded as JPEG in Documents so it survives restarts without bloating
/// the settings JSON that gets backed up to Supabase.
///
/// Cloud sync of the photo (Storage bucket + `profiles.avatar_url`) is a
/// deliberate follow-up — it needs a one-time dashboard change, and the
/// account screen already works with the local copy today.
@MainActor
final class AccountProfileStore: ObservableObject {
    static let shared = AccountProfileStore()

    @Published private(set) var avatarImage: UIImage?

    private let fileURL: URL
    private let maxDimension: CGFloat = 1024
    private let jpegQuality: CGFloat = 0.85

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("profile-avatar.jpg")
        if let data = try? Data(contentsOf: fileURL) {
            avatarImage = UIImage(data: data)
        }
    }

    /// Downscale (so a 48-megapixel camera pick doesn't become a 12 MB file),
    /// re-encode, persist, and publish.
    func save(_ image: UIImage) {
        let resized = Self.downscaled(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            avatarImage = resized
        } catch {
            // Best-effort: a failed write leaves the previous avatar in place.
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
        avatarImage = nil
    }

    /// Initials for the blank placeholder (e.g. "Hmam Kaadna" → "HK").
    static func initials(for fullName: String) -> String {
        let parts = fullName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let joined = parts.joined()
        return joined.isEmpty ? "" : joined.uppercased()
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension, largestSide > 0 else { return image }
        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
