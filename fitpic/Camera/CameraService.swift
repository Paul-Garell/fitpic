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
        DispatchQueue.main.async { self.zoomOptions = Self.buildZoomOptions(for: device) }
        return true
    }

    // MARK: - Zoom option builder

    /// Derives the correct zoom-pill buttons directly from AVFoundation metadata.
    ///
    /// `virtualDeviceSwitchOverVideoZoomFactors` gives the *hardware* `videoZoomFactor`
    /// values at which the system switches physical lenses. Combined with the 1× baseline
    /// we can label them correctly as user-facing multipliers (0.5×, 1×, 2×, 3×…).
    ///
    /// Example — iPhone 15 Pro triple camera:
    ///   switchOverFactors = [2, 6]   (ultra-wide→wide at ×2, wide→tele at ×6)
    ///   ⟹  options: [("0.5×", 1.0), ("1×", 2.0), ("2×", 4.0), ("3×", 6.0)]
    ///
    /// Example — iPhone SE (single camera):
    ///   switchOverFactors = []
    ///   ⟹  options: [("1×", 1.0)]
    private static func buildZoomOptions(for device: AVCaptureDevice) -> [ZoomOption] {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }

        guard !switchOvers.isEmpty else {
            // Single-lens device — just expose 1×
            return [ZoomOption(displayLabel: "1×", deviceFactor: 1.0)]
        }

        // The widest lens sits at deviceFactor = 1.0.
        // Each switchOver value is where the *next* lens begins.
        // User-facing labels count from the widest lens outward.
        // If the device supports an ultra-wide (switchOvers has an entry at the start),
        // the first button is "0.5×" at deviceFactor 1.0 and "1×" at switchOvers[0].
        //
        // Heuristic: a device has ultra-wide if it can zoom below the first switchover
        // at a factor ≤ 1.0 (i.e. minAvailableVideoZoomFactor < switchOvers[0]).
        let hasUltraWide = device.minAvailableVideoZoomFactor < switchOvers[0]

        // Build raw device-factor list
        var deviceFactors: [CGFloat] = hasUltraWide ? [1.0] : []
        deviceFactors.append(contentsOf: switchOvers)

        // Build user-facing multipliers: starting from the widest end.
        // If ultra-wide exists the steps are 0.5×, 1×, 2×, 3×…
        // Otherwise they start at 1×, 2×, 3×…
        let userMultipliers: [Double] = {
            let start: Double = hasUltraWide ? 0.5 : 1.0
            return deviceFactors.enumerated().map { start * pow(2.0, Double($0.offset)) }
        }()

        let options = zip(deviceFactors, userMultipliers).map { (deviceFactor, userMult) in
            ZoomOption(
                displayLabel: userMult < 1 ? String(format: "%.1g×", userMult) : "\(Int(userMult))×",
                deviceFactor: deviceFactor
            )
        }

        // Clamp to what the device actually supports
        return options.filter {
            $0.deviceFactor >= device.minAvailableVideoZoomFactor &&
            $0.deviceFactor <= device.maxAvailableVideoZoomFactor
        }
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
            DispatchQueue.main.async { self.zoomFactor = 1.0 }
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
        DispatchQueue.main.async { self.capturedImage = image }
    }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
