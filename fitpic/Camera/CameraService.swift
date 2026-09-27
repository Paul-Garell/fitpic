import AVFoundation
import UIKit
import Combine

// MARK: - CameraService

/// Owns the AVCaptureSession and exposes controls for flash, lens flip, zoom, and capture.
/// All session mutations happen on a dedicated background queue.
final class CameraService: NSObject, ObservableObject {

    // MARK: Published state

    @Published var isFlashOn: Bool = false
    @Published var isFrontCamera: Bool = false
    @Published var zoomFactor: CGFloat = 1.0          // mirrors device.videoZoomFactor
    @Published var zoomOptions: [ZoomOption] = []     // buttons to show in the UI
    @Published var capturedImage: UIImage?
    @Published var error: CameraError?

    /// Width-to-height ratio the captured photo is cropped to.
    /// Defaults to the feed cell ratio so the saved file matches what the feed displays.
    /// Set to `nil` to keep the full sensor frame uncropped.
    var captureAspectRatio: CGFloat? = FitPicCell.defaultAspectRatio

    // MARK: Types

    /// A zoom preset the user can tap.
    /// `displayLabel` is what the pill shows ("0.5×", "1×", "2×" …).
    /// `deviceFactor` is the raw `videoZoomFactor` value to send to AVFoundation.
    struct ZoomOption: Identifiable, Equatable {
        let id = UUID()
        let displayLabel: String
        let deviceFactor: CGFloat
    }

    // MARK: Private

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.fitpic.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?

    // MARK: Error

    enum CameraError: Error, LocalizedError {
        case permissionDenied
        case deviceUnavailable
        case configurationFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:                  return "Camera access denied. Enable it in Settings."
            case .deviceUnavailable:                 return "No suitable camera found."
            case .configurationFailed(let msg):      return "Camera setup failed: \(msg)"
            }
        }
    }

    // MARK: Lifecycle

    func start() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: Configuration

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard addVideoInput(position: isFrontCamera ? .front : .back) else {
            DispatchQueue.main.async { self.error = .deviceUnavailable }
            return
        }

        guard session.canAddOutput(photoOutput) else {
            DispatchQueue.main.async { self.error = .configurationFailed("Cannot add photo output") }
            return
        }
        session.addOutput(photoOutput)
    }

    @discardableResult
    private func addVideoInput(position: AVCaptureDevice.Position) -> Bool {
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .forEach { session.removeInput($0) }

        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]

        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: position
        ).devices

        guard let device = discovered.first ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return false }

        session.addInput(input)
        currentDevice = device

        let options = Self.buildZoomOptions(for: device)
        DispatchQueue.main.async { self.zoomOptions = options }

        // Open at the "1×" lens rather than the widest (0.5×) lens.
        applyDefaultZoom(device: device, options: options)
        return true
    }

    /// Sets the initial zoom to the user-facing 1× option if present, else the widest.
    private func applyDefaultZoom(device: AVCaptureDevice, options: [ZoomOption]) {
        let target = options.first { $0.displayLabel == "1×" }?.deviceFactor ?? 1.0
        let clamped = target.clamped(
            to: device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor
        )
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.zoomFactor = clamped }
        } catch {
            print("[CameraService] default zoom error: \(error)")
        }
    }

    // MARK: - Zoom option builder

    /// Derives the correct zoom-pill buttons directly from AVFoundation metadata.
    ///
    /// `virtualDeviceSwitchOverVideoZoomFactors` gives the *hardware* `videoZoomFactor`
    /// values at which the system switches physical lenses. The widest lens always sits
    /// at deviceFactor 1.0. The user-facing "1×" baseline is the main wide lens — i.e.
    /// the first switch-over factor when an ultra-wide exists, otherwise 1.0.
    ///
    /// Each user-facing multiplier is simply `deviceFactor / baseline`.
    ///
    /// Example — triple camera reporting switchOvers = [2, 6]:
    ///   baseline = 2.0 (wide lens)
    ///   • deviceFactor 1.0 → 1.0/2.0 = 0.5×   (ultra-wide)
    ///   • deviceFactor 2.0 → 2.0/2.0 = 1×      (wide)
    ///   • deviceFactor 6.0 → 6.0/2.0 = 3×      (tele)
    ///
    /// Example — dual wide+tele reporting switchOvers = [2]:
    ///   baseline = 1.0 (no ultra-wide)
    ///   • deviceFactor 1.0 → 1×
    ///   • deviceFactor 2.0 → 2×
    ///
    /// Example — single camera, switchOvers = []:
    ///   ⟹ [("1×", 1.0)]
    private static func buildZoomOptions(for device: AVCaptureDevice) -> [ZoomOption] {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }

        guard !switchOvers.isEmpty else {
            // Single-lens device — just expose 1×.
            return [ZoomOption(displayLabel: "1×", deviceFactor: 1.0)]
        }

        // A device has an ultra-wide if it can zoom out below its first lens switch-over.
        let hasUltraWide = device.minAvailableVideoZoomFactor < switchOvers[0]

        // Candidate hardware zoom stops: the widest lens (1.0) plus every switch-over point.
        var deviceFactors: [CGFloat] = hasUltraWide ? [1.0] : []
        deviceFactors.append(contentsOf: switchOvers)

        // The user-facing "1×" corresponds to the main wide lens:
        //   • with ultra-wide  → the first switch-over factor (ultra-wide→wide)
        //   • without          → 1.0
        let baseline: CGFloat = hasUltraWide ? switchOvers[0] : 1.0

        let options = deviceFactors.map { deviceFactor -> ZoomOption in
            let userMultiplier = deviceFactor / baseline
            return ZoomOption(
                displayLabel: Self.zoomLabel(for: userMultiplier),
                deviceFactor: deviceFactor
            )
        }

        // Clamp to what the device actually supports.
        return options.filter {
            $0.deviceFactor >= device.minAvailableVideoZoomFactor &&
            $0.deviceFactor <= device.maxAvailableVideoZoomFactor
        }
    }

    /// Formats a user-facing zoom multiplier: "0.5×", "1×", "2×", "3.5×".
    private static func zoomLabel(for multiplier: CGFloat) -> String {
        // Whole numbers render without a decimal; fractional values keep one decimal.
        if abs(multiplier.rounded() - multiplier) < 0.05 {
            return "\(Int(multiplier.rounded()))×"
        }
        return String(format: "%.1f×", multiplier)
    }

    // MARK: Controls

    func toggleFlash() { isFlashOn.toggle() }

    func flipCamera() {
        isFrontCamera.toggle()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            addVideoInput(position: isFrontCamera ? .front : .back)
            session.commitConfiguration()
            // addVideoInput applies the default (1×) zoom for the new device.
        }
    }

    func setZoom(_ deviceFactor: CGFloat) {
        guard let device = currentDevice else { return }
        let clamped = deviceFactor.clamped(
            to: device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor
        )
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.zoomFactor = clamped }
            } catch {
                print("[CameraService] setZoom error: \(error)")
            }
        }
    }

    // MARK: Capture

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = isFlashOn ? .on : .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error { print("[CameraService] capture error: \(error)"); return }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        let finalImage = captureAspectRatio.map { image.croppedToAspectRatio($0) } ?? image
        DispatchQueue.main.async { self.capturedImage = finalImage }
    }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
