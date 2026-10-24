import AVFoundation
import UIKit

/// Minimal AVFoundation capture: one back camera, photo output, torch toggle.
///
/// The torch button is a first-class control, not an afterthought — izakayas
/// are dark, and the PRD calls for it to be prominent.
@MainActor
final class CameraController: NSObject, ObservableObject {
    @Published var isAvailable = false
    @Published var torchOn = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var photoContinuation: CheckedContinuation<Data, Error>?

    enum CameraError: Error {
        case unavailable
        case captureFailed
    }

    func start() async {
        // Simulator, or a device without a usable camera: don't even ask for
        // permission. The library picker (and the bundled sample) remain as
        // the capture path.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            isAvailable = false
            return
        }
        guard await requestPermission(), let input = try? AVCaptureDeviceInput(device: device) else {
            isAvailable = false
            return
        }

        self.device = device
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()

        let session = self.session
        Task.detached { session.startRunning() }
        isAvailable = true
    }

    func stop() {
        let session = self.session
        Task.detached { session.stopRunning() }
    }

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
            torchOn = device.torchMode == .on
        } catch {
            // Torch failure is cosmetic; ignore.
        }
    }

    func capturePhoto() async throws -> Data {
        guard isAvailable else { throw CameraError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            if let data {
                photoContinuation?.resume(returning: data)
            } else {
                photoContinuation?.resume(throwing: error ?? CameraError.captureFailed)
            }
            photoContinuation = nil
        }
    }
}
