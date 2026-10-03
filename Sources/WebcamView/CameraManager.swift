import Foundation
import AVFoundation
import AppKit

enum CameraError: Error, LocalizedError {
    case noDeviceAvailable
    case permissionDenied
    case cannotAddInput

    var errorDescription: String? {
        switch self {
        case .noDeviceAvailable:
            return "No camera found. Please connect a camera and try again."
        case .permissionDenied:
            return "WebcamView needs camera access. Enable it in System Settings > Privacy & Security > Camera."
        case .cannotAddInput:
            return "Could not configure the camera."
        }
    }
}

/// Owns the `AVCaptureSession` and provides the preview layer that the window
/// displays. Rebuilt the input automatically after sleep and when the current
/// camera is unplugged so the preview never stays permanently black.
final class CameraManager: NSObject {

    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    var currentDevice: AVCaptureDevice? { device }

    // MARK: - Init / observers

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceWasDisconnected(_:)),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    func setup() async throws {
        // Verify / request camera permission.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.permissionDenied }
        default:
            throw CameraError.permissionDenied
        }

        // Prefer the user's saved camera, otherwise fall back to the default.
        let chosen: AVCaptureDevice?
        if let savedID = Preferences.shared.cameraID {
            chosen = Self.availableCameras().first { $0.uniqueID == savedID }
                ?? AVCaptureDevice.default(for: .video)
        } else {
            chosen = AVCaptureDevice.default(for: .video)
        }
        guard let chosen else { throw CameraError.noDeviceAvailable }

        let newSession = AVCaptureSession()
        newSession.beginConfiguration()

        let newInput = try AVCaptureDeviceInput(device: chosen)
        guard newSession.canAddInput(newInput) else {
            newSession.commitConfiguration()
            throw CameraError.cannotAddInput
        }
        newSession.addInput(newInput)

        if newSession.canSetSessionPreset(.high) {
            newSession.sessionPreset = .high
        }
        newSession.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: newSession)
        layer.videoGravity = .resizeAspectFill

        self.session = newSession
        self.device = chosen
        self.input = newInput
        self.previewLayer = layer
    }

    // MARK: - Session control

    func startSession() {
        guard let session, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func stopSession() {
        guard let session, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    // MARK: - Device enumeration

    static func availableCameras() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices
    }

    /// User-driven camera switch; remembers the choice for next launch.
    func switchToCamera(_ device: AVCaptureDevice) async throws {
        try await rebuildInput(for: device)
        Preferences.shared.cameraID = device.uniqueID
    }

    // MARK: - Recovery

    @objc private func systemDidWake() {
        guard let device else { return }
        Task { try? await self.rebuildInput(for: device) }
    }

    @objc private func deviceWasDisconnected(_ note: Notification) {
        guard let detached = note.object as? AVCaptureDevice,
              detached.uniqueID == device?.uniqueID else { return }
        let fallback = AVCaptureDevice.default(for: .video)
            ?? Self.availableCameras().first { $0.uniqueID != detached.uniqueID }
        guard let fallback else { return }
        Task { try? await self.rebuildInput(for: fallback) }
    }

    /// Replaces the capture input for `device` without touching the saved
    /// preference (so a transient fallback never overwrites the user's choice).
    private func rebuildInput(for device: AVCaptureDevice) async throws {
        guard let session else { return }

        let wasRunning = session.isRunning
        if wasRunning {
            stopSession()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        session.beginConfiguration()
        if let oldInput = input {
            session.removeInput(oldInput)
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            self.input = newInput
            self.device = device
        }
        session.commitConfiguration()

        if wasRunning {
            startSession()
        }
    }
}
