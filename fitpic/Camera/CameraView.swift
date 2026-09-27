import SwiftUI
import PhotosUI

// MARK: - CameraView

/// Full-screen camera sheet.
/// Owns the entire capture flow: live preview → photo review → tag entry.
/// Only calls `onComplete` once the user has finished tagging and tapped Save/Skip.
struct CameraView: View {

    var onComplete: (UIImage, [String]) -> Void
    var onDismiss: () -> Void

    /// Aspect ratio of the framed capture area. Matches the feed cell so that
    /// what the user frames is exactly what they see in the feed.
    var captureAspectRatio: CGFloat = FitPicCell.defaultAspectRatio

    @StateObject private var camera = CameraService()
    @GestureState private var pinchStartZoom: CGFloat? = nil

    // Internal flow state — no sheet nesting crosses a view boundary
    @State private var previewImage: UIImage? = nil
    @State private var acceptedImage: UIImage? = nil   // set after green-check; triggers tag sheet
    @State private var pendingTags: [String] = []

    // Photo-library upload
    @State private var pickerItem: PhotosPickerItem? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Spacer(minLength: 0)

                // Live preview constrained to the capture aspect ratio,
                // so the framed area equals the saved/feed result.
                CameraPreviewView(session: camera.session)
                    .aspectRatio(captureAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .gesture(pinchGesture)

                Spacer(minLength: 0)
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .onAppear {
            camera.captureAspectRatio = captureAspectRatio
            camera.start()
        }
        .onDisappear { camera.stop() }
        // Step 1: photo captured → show review screen
        .fullScreenCover(item: $previewImage.asIdentifiable) { wrapper in
            PhotoPreviewView(
                image: wrapper.value,
                aspectRatio: captureAspectRatio,
                onRetake: { previewImage = nil },
                onAccept: { image in
                    previewImage = nil
                    pendingTags = []
                    acceptedImage = image
                }
            )
        }
        // Step 2: photo accepted → show tag entry
        .sheet(item: $acceptedImage.asIdentifiable) { wrapper in
            AddTagsView(
                tags: $pendingTags,
                onSubmit: {
                    onComplete(wrapper.value, pendingTags)
                }
            )
        }
        // Sink new captures from CameraService into local state
        .onChange(of: camera.capturedImage) { _, image in
            guard let image else { return }
            previewImage = image
            camera.capturedImage = nil
        }
        // Sink photo-library selections into the same review pipeline
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            loadPickedPhoto(item)
        }
    }

    // MARK: Photo-library loading

    private func loadPickedPhoto(_ item: PhotosPickerItem) {
        Task {
            defer { pickerItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            // Crop to the same aspect ratio the camera uses so preview/feed match.
            let cropped = image.croppedToAspectRatio(captureAspectRatio)
            await MainActor.run { previewImage = cropped }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                CameraControlIcon(systemName: "xmark")
            }
            Spacer()
            Button(action: camera.toggleFlash) {
                CameraControlIcon(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
            }
            Button(action: camera.flipCamera) {
                CameraControlIcon(systemName: "camera.rotate.fill")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 20) {
            if camera.zoomOptions.count > 1 {
                zoomPill
            }
            captureRow
        }
        .padding(.bottom, 40)
    }

    /// Library button (left) · shutter (center) · spacer (right) to keep the shutter centered.
    private var captureRow: some View {
        ZStack {
            shutterButton

            HStack {
                photoLibraryButton
                Spacer()
            }
            .padding(.horizontal, 36)
        }
    }

    private var photoLibraryButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var shutterButton: some View {
        Button(action: camera.capturePhoto) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
            }
        }
    }

    private var zoomPill: some View {
        HStack(spacing: 0) {
            ForEach(camera.zoomOptions) { option in
                Button { camera.setZoom(option.deviceFactor) } label: {
                    Text(option.displayLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isZoomSelected(option) ? .black : .white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(isZoomSelected(option) ? Color.white : Color.clear)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.45))
        .clipShape(Capsule())
    }

    // MARK: Gestures

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchStartZoom) { value, state, _ in
                if state == nil { state = camera.zoomFactor }
                camera.setZoom((state ?? 1.0) * value)
            }
    }

    // MARK: Helpers

    private func isZoomSelected(_ option: CameraService.ZoomOption) -> Bool {
        abs(camera.zoomFactor - option.deviceFactor) < 0.15
    }
}

// MARK: - CameraControlIcon

private struct CameraControlIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.35))
            .clipShape(Circle())
    }
}

// MARK: - IdentifiableWrapper + Optional extension

/// Lightweight Identifiable box so any value type can drive `.sheet(item:)`.
struct IdentifiableWrapper<T>: Identifiable {
    let id = UUID()
    let value: T
}

extension Optional {
    /// Projects an Optional into an Optional<IdentifiableWrapper> suitable for
    /// `.sheet(item:)` and `.fullScreenCover(item:)`.
    var asIdentifiable: IdentifiableWrapper<Wrapped>? {
        get { self.map(IdentifiableWrapper.init) }
        set { self = newValue?.value }
    }
}
