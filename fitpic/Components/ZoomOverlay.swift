import SwiftUI
import Combine

// MARK: - ZoomOverlayModel

/// Shared state driving the app-level zoom overlay.
/// A feed image publishes its live pinch state here; the overlay (hosted above
/// everything at the app root) renders a floating copy so it can visually expand
/// outside any scroll view or cell clipping.
final class ZoomOverlayModel: ObservableObject {
    /// The image currently being pinch-zoomed, or nil when idle.
    @Published var image: UIImage?
    /// The on-screen frame (global coordinates) of the source image at rest.
    @Published var sourceFrame: CGRect = .zero
    /// Current pinch scale (>= 1).
    @Published var scale: CGFloat = 1
    /// Focal anchor within the image (0...1), where the pinch is centered.
    @Published var anchor: UnitPoint = .center
    /// Extra translation from a two-finger drag while zooming.
    @Published var translation: CGSize = .zero
    /// Identity of the cell currently zooming (so it can hide its in-feed copy).
    @Published var sourceID: UUID?

    var isActive: Bool { image != nil }

    func begin(image: UIImage, sourceFrame: CGRect, sourceID: UUID) {
        self.image = image
        self.sourceFrame = sourceFrame
        self.sourceID = sourceID
        self.scale = 1
        self.anchor = .center
        self.translation = .zero
    }

    func update(scale: CGFloat, anchor: UnitPoint, translation: CGSize) {
        self.scale = max(1, scale)
        self.anchor = anchor
        self.translation = translation
    }

    func end() {
        image = nil
        sourceID = nil
        scale = 1
        anchor = .center
        translation = .zero
    }
}

// MARK: - ZoomOverlay

/// Draws the zooming image above all other content. Placed once, at the app root.
struct ZoomOverlay: View {
    @ObservedObject var model: ZoomOverlayModel

    var body: some View {
        GeometryReader { _ in
            if let image = model.image {
                // Dim backdrop that intensifies as you zoom in.
                Color.black
                    .opacity(min((model.scale - 1) * 0.6, 0.6))
                    .ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: model.sourceFrame.width, height: model.sourceFrame.height)
                    .clipped()
                    // Scale around the pinch focal point so it zooms where the
                    // fingers are, not always the middle.
                    .scaleEffect(model.scale, anchor: model.anchor)
                    // Two-finger drag moves the image around.
                    .offset(model.translation)
                    .position(x: model.sourceFrame.midX, y: model.sourceFrame.midY)
            }
        }
        .allowsHitTesting(false)   // purely visual; gestures live on the source image
        .ignoresSafeArea()
    }
}
