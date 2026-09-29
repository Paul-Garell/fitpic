import UIKit
import ImageIO

// MARK: - ImageStorage

/// Responsible for persisting and retrieving fit-pic images on disk.
/// All paths are relative to the user's Documents directory.
final class ImageStorage {

    static let shared = ImageStorage()
    private init() {}

    private let fileManager = FileManager.default
    private let subdirectory = "FitPics"

    // MARK: Write

    /// Writes `image` to disk and returns its relative path, or `nil` on failure.
    /// - Parameter subdirectory: Optional override of the default "FitPics" folder
    ///   (e.g. "Closet" for garment thumbnails).
    func save(_ image: UIImage, subdirectory: String? = nil) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        let relativePath = "\(subdirectory ?? self.subdirectory)/\(filename)"

        guard let url = absoluteURL(for: relativePath) else { return nil }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
            try data.write(to: url)
            return relativePath
        } catch {
            print("[ImageStorage] save error: \(error)")
            return nil
        }
    }

    // MARK: Read

    /// Loads the image at the given relative path, or `nil` if not found.
    func load(path: String) -> UIImage? {
        guard let url = absoluteURL(for: path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Loads a downsampled thumbnail for the given path, sized to roughly
    /// `maxPixelSize` points on its longest edge (multiplied internally for retina).
    /// Efficient for small UI like calendar cells.
    func loadThumbnail(path: String, maxPixelSize: CGFloat) -> UIImage? {
        guard let url = absoluteURL(for: path) else { return nil }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        // Assume a 3x retina budget so thumbnails stay crisp on any device;
        // the extra pixels are negligible at these small sizes.
        let pixelBudget = maxPixelSize * 3
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelBudget
        ] as CFDictionary

        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        return UIImage(cgImage: cgThumb)
    }

    // MARK: Delete

    @discardableResult
    func delete(path: String) -> Bool {
        guard let url = absoluteURL(for: path) else { return false }
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            print("[ImageStorage] delete error: \(error)")
            return false
        }
    }

    // MARK: Private

    private func absoluteURL(for relativePath: String) -> URL? {
        fileManager
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(relativePath)
    }
}
