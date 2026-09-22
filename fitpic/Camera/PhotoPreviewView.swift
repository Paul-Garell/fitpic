import SwiftUI

// MARK: - PhotoPreviewView

/// Full-screen preview of a just-captured photo.
/// Offers retake (red ✕) or accept (green ✓).
struct PhotoPreviewView: View {

    let image: UIImage
    var onRetake: () -> Void
    var onAccept: (UIImage) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()

            VStack {
                Spacer()

                HStack(spacing: 60) {
                    // Retake
                    Button(action: onRetake) {
                        ActionButton(systemName: "xmark", color: .red)
                    }

                    // Accept
                    Button { onAccept(image) } label: {
                        ActionButton(systemName: "checkmark", color: .green)
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - ActionButton

private struct ActionButton: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 26, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 64, height: 64)
            .background(color)
            .clipShape(Circle())
            .shadow(radius: 6)
    }
}
