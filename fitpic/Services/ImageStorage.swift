import UIKit

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
    func save(_ image: UIImage) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        let relativePath = "\(subdirectory)/\(filename)"

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
