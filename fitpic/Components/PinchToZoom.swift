import SwiftUI

// MARK: - PinchToZoom

/// Instagram-style pinch-to-zoom for a feed image.
///
/// A UIKit gesture layer (below) recognizes a two-finger pinch + pan and drives
/// the app-level `ZoomOverlay`, which draws the image above everything (outside
/// scroll/cell clipping) while zooming and hides it on release.
///
/// - Only multi-touch sequences are intercepted, so one-finger scrolling in the
///   feed is unaffected.
/// - A single UIKit recognizer set handles the whole gesture, so there is no
///   fragile mid-gesture swapping (which previously left the zoom stuck).
///
/// Requires a `ZoomOverlayModel` in the environment and `ZoomOverlay(model:)`
/// hosted at the app root.
struct PinchToZoom: ViewModifier {
    let image: UIImage?

    @EnvironmentObject private var overlay: ZoomOverlayModel
    @State private var sourceFrame: CGRect = .zero
    /// Stable identity for this cell instance, so the overlay knows who is zooming.
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { sourceFrame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, new in
                            sourceFrame = new
                        }
                }
            )
            .opacity(overlay.sourceID == token && overlay.isActive ? 0 : 1)
            .overlay(
                PinchGestureView(
                    onBegin: {
                        guard let image else { return }
                        overlay.begin(image: image, sourceFrame: sourceFrame, sourceID: token)
                    },
                    onChange: { scale, anchor, translation in
                        guard overlay.sourceID == token else { return }
                        overlay.update(scale: scale, anchor: anchor, translation: translation)
                    },
                    onEnd: {
                        guard overlay.sourceID == token else { return }
                        overlay.end()
                    }
                )
            )
    }
}

extension View {
    /// Enables pinch-to-zoom that pops the given image above all content while
    /// pinching (via the app-level ZoomOverlay). One-finger scrolling is unaffected.
    func pinchToZoom(image: UIImage?) -> some View {
        modifier(PinchToZoom(image: image))
    }
}

// MARK: - PinchGestureView (UIKit)

/// Hosts pinch + two-finger pan recognizers, reporting scale, focal anchor
/// (0...1 within the view), and translation. Only intercepts multi-touch.
private struct PinchGestureView: UIViewRepresentable {
    var onBegin: () -> Void
    var onChange: (_ scale: CGFloat, _ anchor: UnitPoint, _ translation: CGSize) -> Void
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GestureView {
        let view = GestureView()
        view.backgroundColor = .clear

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handle(_:))
        )
        pinch.delegate = context.coordinator
        pinch.cancelsTouchesInView = false   // let underlying scroll still receive touches
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handle(_:))
        )
        pan.delegate = context.coordinator
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)

        context.coordinator.pinch = pinch
        context.coordinator.pan = pan
        return view
    }

    func updateUIView(_ uiView: GestureView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PinchGestureView
        weak var pinch: UIPinchGestureRecognizer?
        weak var pan: UIPanGestureRecognizer?

        private var active = false
        private var anchor: UnitPoint = .center

        init(_ parent: PinchGestureView) { self.parent = parent }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handle(_ gesture: UIGestureRecognizer) {
            guard let view = gesture.view else { return }
            let scale = pinch?.scale ?? 1
            let panTranslation = pan?.translation(in: view) ?? .zero

            switch gesture.state {
            case .began:
                if !active {
                    active = true
                    // Capture focal point (in view's unit space) at the start.
                    if let pinch, pinch.numberOfTouches >= 2 {
                        let mid = pinch.location(in: view)
                        anchor = UnitPoint(
                            x: view.bounds.width > 0 ? mid.x / view.bounds.width : 0.5,
                            y: view.bounds.height > 0 ? mid.y / view.bounds.height : 0.5
                        )
                    }
                    parent.onBegin()
                }
            case .changed:
                guard active else { return }
                parent.onChange(
                    max(1, scale),
                    anchor,
                    CGSize(width: panTranslation.x, height: panTranslation.y)
                )
            case .ended, .cancelled, .failed:
                // End only when both recognizers are no longer active.
                let pinchDone = (pinch?.state != .began && pinch?.state != .changed)
                let panDone = (pan?.state != .began && pan?.state != .changed)
                if active, pinchDone, panDone {
                    active = false
                    parent.onEnd()
                }
            default:
                break
            }
        }
    }

    // MARK: Gesture view

    /// Receives touches so its recognizers can observe them. Because the pinch/pan
    /// recognizers use `cancelsTouchesInView = false`, touches still propagate to the
    /// underlying ScrollView, so single-finger scrolling continues to work.
    final class GestureView: UIView {}
}
