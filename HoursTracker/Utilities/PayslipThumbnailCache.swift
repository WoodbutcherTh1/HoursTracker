import Foundation
import UIKit
import PDFKit
import ImageIO

/// Regenerable square thumbnails for the payslip library.
///
/// Stored under the app **Caches** directory (not App Group / Documents) so they are
/// never packaged into `.htbackup.zip` alongside `payslips/files/` binaries.
final class PayslipThumbnailCache {
    static let shared = PayslipThumbnailCache()

    static let thumbnailPixelSize: CGFloat = 360

    private let fileManager: FileManager
    private let memoryCache = NSCache<NSString, UIImage>()
    private let cacheDirectory: URL
    private let queue = DispatchQueue(label: "com.hourstracker.payslip-thumbnails", qos: .userInitiated)

    init(
        fileManager: FileManager = .default,
        cacheDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.cacheDirectory = caches.appendingPathComponent("PayslipThumbnails", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        memoryCache.countLimit = 64
    }

    /// Absolute path used for disk cache — must stay outside App Group payslip storage.
    var directoryURL: URL { cacheDirectory }

    func cachedImage(for id: UUID) -> UIImage? {
        let key = id.uuidString as NSString
        if let memory = memoryCache.object(forKey: key) {
            return memory
        }
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        memoryCache.setObject(image, forKey: key)
        return image
    }

    func fileURL(for id: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(id.uuidString).jpg")
    }

    func remove(id: UUID) {
        memoryCache.removeObject(forKey: id.uuidString as NSString)
        let url = fileURL(for: id)
        try? fileManager.removeItem(at: url)
    }

    func removeAll() {
        memoryCache.removeAllObjects()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Returns a cached thumbnail or generates one asynchronously from the source file.
    func thumbnail(
        for record: PayslipRecord,
        sourceURL: URL,
        completion: @escaping (UIImage?) -> Void
    ) {
        if let cached = cachedImage(for: record.id) {
            completion(cached)
            return
        }

        let id = record.id
        let kind = record.sourceKind
        let pixelSize = Self.thumbnailPixelSize
        let diskURL = fileURL(for: id)

        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let image: UIImage?
            switch kind {
            case .pdf:
                image = Self.renderPDFThumbnail(at: sourceURL, pixelSize: pixelSize)
            case .image:
                image = Self.renderImageThumbnail(at: sourceURL, pixelSize: pixelSize)
            }

            if let image, let data = image.jpegData(compressionQuality: 0.82) {
                try? data.write(to: diskURL, options: .atomic)
                self.memoryCache.setObject(image, forKey: id.uuidString as NSString)
            }

            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    // MARK: - Rendering

    static func renderPDFThumbnail(at url: URL, pixelSize: CGFloat) -> UIImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            return nil
        }
        let size = CGSize(width: pixelSize, height: pixelSize)
        // PDFKit API — real first-page raster, not a placeholder icon.
        return page.thumbnail(of: size, for: .mediaBox)
    }

    static func renderImageThumbnail(at url: URL, pixelSize: CGFloat) -> UIImage? {
        let maxPixel = Int(pixelSize)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Fallback if ImageIO fails.
            guard let data = try? Data(contentsOf: url),
                  let full = UIImage(data: data) else {
                return nil
            }
            return downsample(full, maxPixel: pixelSize)
        }
        return UIImage(cgImage: cgImage)
    }

    private static func downsample(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxPixel, maxSide > 0 else { return image }
        let scale = maxPixel / maxSide
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
