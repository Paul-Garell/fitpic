import UIKit

// MARK: - UIImage aspect-ratio cropping

extension UIImage {
    /// Returns a center-cropped copy matching the given width:height ratio.
    /// Normalizes orientation first so the pixel buffer matches the visual layout.
    func croppedToAspectRatio(_ ratio: CGFloat) -> UIImage {
        let normalized = normalizedUp()
        guard let cg = normalized.cgImage else { return normalized }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let currentRatio = width / height

        let cropRect: CGRect
        if currentRatio > ratio {
            // Too wide — trim the sides.
            let newWidth = height * ratio
            cropRect = CGRect(x: (width - newWidth) / 2, y: 0, width: newWidth, height: height)
        } else {
            // Too tall — trim top/bottom.
            let newHeight = width / ratio
            cropRect = CGRect(x: 0, y: (height - newHeight) / 2, width: width, height: newHeight)
        }

        guard let cropped = cg.cropping(to: cropRect.integral) else { return normalized }
        return UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up)
    }

    /// Redraws the image with `.up` orientation so its pixel buffer matches its visual layout.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
