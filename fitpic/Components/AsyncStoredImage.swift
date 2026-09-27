import SwiftUI

// MARK: - AsyncStoredImage

/// Loads a stored fit-pic image off the main thread and displays it once ready.
/// Prevents synchronous full-resolution JPEG decodes from blocking scrolling.
///
/// - Parameters:
///   - path: Relative image path within the fit-pic store.
///   - targetWidth: Approximate display width in points; the image is downsampled
///     to about this size (× a retina budget) to keep memory and decode cost low.
struct AsyncStoredImage: View {

    let path: String
    let targetWidth: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemFill))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        // Reload only when the path or target size meaningfully changes.
        .task(id: LoadKey(path: path, width: Int(targetWidth.rounded()))) {
            image = await Self.load(path: path, targetWidth: targetWidth)
        }
    }

    // MARK: Loading

    private struct LoadKey: Equatable {
        let path: String
        let width: Int
    }

    private static func load(path: String, targetWidth: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Downsample to the display size rather than decoding full-res.
                let thumb = ImageStorage.shared.loadThumbnail(
                    path: path,
                    maxPixelSize: max(targetWidth, 1)
                )
                continuation.resume(returning: thumb)
            }
        }
    }
}
