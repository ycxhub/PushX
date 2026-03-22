import AVFoundation
import CoreVideo
import UIKit
import ImageIO

enum CameraConfigurationError: Error, LocalizedError {
    case noCameraDevice
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraDevice:
            return "No camera is available. Use a physical iPhone, or enable a camera in the Simulator (I/O → Camera)."
        case .cannotAddInput:
            return "Could not open the camera. Close other apps that might be using it and try again."
        case .cannotAddOutput:
            return "Could not start video capture. Try force-quitting and reopening the app."
        }
    }
}

final class CameraManager: NSObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.pushupcoach.capture.session", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.pushupcoach.camera", qos: .userInteractive)

    private let providerLock = NSLock()
    private var _poseProvider: (any PoseProvider)?

    private var poseProvider: (any PoseProvider)? {
        get {
            providerLock.lock()
            defer { providerLock.unlock() }
            return _poseProvider
        }
        set {
            providerLock.lock()
            _poseProvider = newValue
            providerLock.unlock()
        }
    }

    private let devicePosition: AVCaptureDevice.Position = .front

    var onPoseResult: ((PoseResult?) -> Void)?
    var onFrameProcessed: (() -> Void)?
    var onStartupEvent: ((String) -> Void)?

    /// Picks front ultra-wide when available (wider FOV at arm’s length), else wide angle.
    private static func preferredFrontCameraDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        let devices = discovery.devices
        for device in devices where device.position == .front {
            if device.deviceType == .builtInUltraWideCamera {
                return device
            }
        }
        if let first = devices.first { return first }
        // Discovery can be empty on some runtimes; `default` still resolves the front camera.
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }

    /// Stops (if needed), reconfigures I/O, then starts. All session work runs on `sessionQueue` to avoid deadlocks on restart.
    ///
    /// Completion is invoked **synchronously on `sessionQueue`** (not `DispatchQueue.main`). Callers should hop to
    /// `@MainActor` themselves — using `main.async` here can fail to interleave with Swift `MainActor` tasks that
    /// are suspended on `await`, which left the start button stuck on “Starting…”.
    func configureAndStart(provider: any PoseProvider, completion: ((Error?) -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            let completionLock = NSLock()
            var didFinish = false
            let finish: (Error?) -> Void = { error in
                completionLock.lock()
                defer { completionLock.unlock() }
                guard !didFinish else { return }
                didFinish = true
                completion?(error)
            }

            guard let self else {
                finish(CameraConfigurationError.noCameraDevice)
                return
            }

            self.emitStartupEvent("startup: entered session queue")
            self.poseProvider = provider
            self.emitStartupEvent("startup: selected provider \(provider.providerType.rawValue)")

            if self.session.isRunning {
                self.emitStartupEvent("startup: stopping existing session")
                self.session.stopRunning()
                var spins = 0
                while self.session.isRunning, spins < 200 {
                    Thread.sleep(forTimeInterval: 0.025)
                    spins += 1
                }
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .medium
            self.emitStartupEvent("startup: began configuration")

            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }
            self.emitStartupEvent("startup: cleared previous inputs and outputs")

            guard let camera = Self.preferredFrontCameraDevice(),
                  let deviceInput = try? AVCaptureDeviceInput(device: camera) else {
                self.session.commitConfiguration()
                self.emitStartupEvent("startup failed: no front camera device")
                finish(CameraConfigurationError.noCameraDevice)
                return
            }
            self.emitStartupEvent("startup: resolved camera \(camera.localizedName)")

            guard self.session.canAddInput(deviceInput) else {
                self.session.commitConfiguration()
                self.emitStartupEvent("startup failed: cannot add input")
                finish(CameraConfigurationError.cannotAddInput)
                return
            }
            self.session.addInput(deviceInput)
            self.emitStartupEvent("startup: added input")

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            ]
            videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)

            guard self.session.canAddOutput(videoOutput) else {
                self.session.commitConfiguration()
                self.emitStartupEvent("startup failed: cannot add output")
                finish(CameraConfigurationError.cannotAddOutput)
                return
            }
            self.session.addOutput(videoOutput)
            self.emitStartupEvent("startup: added video output")

            if let connection = videoOutput.connection(with: .video) {
                CapturePortraitConfiguration.applyPortraitMirroredFrontCamera(to: connection)
                self.emitStartupEvent("startup: configured portrait mirrored connection")
            }

            self.session.commitConfiguration()
            self.emitStartupEvent("startup: committed configuration")

            // Unblock UI before `startRunning()` — it can block this queue for a long time.
            self.emitStartupEvent("startup: invoking completion before startRunning()")
            finish(nil)
            self.emitStartupEvent("startup: calling startRunning()")
            self.session.startRunning()
            self.emitStartupEvent("startup: startRunning() returned (isRunning=\(self.session.isRunning))")
        }
    }

    /// Stops capture and waits until the session is no longer running (on `sessionQueue`) before calling completion.
    func stop(completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?() }
                return
            }
            if self.session.isRunning {
                self.session.stopRunning()
                var spins = 0
                while self.session.isRunning, spins < 200 {
                    Thread.sleep(forTimeInterval: 0.025)
                    spins += 1
                }
            }
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    func switchProvider(_ provider: any PoseProvider) {
        poseProvider = provider
    }

    func clearOutputCallbacks() {
        onPoseResult = nil
        onFrameProcessed = nil
        onStartupEvent = nil
    }

    private func emitStartupEvent(_ message: String) {
        onStartupEvent?(message)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let provider = poseProvider else { return }

        let orientation = VisionOrientation.cgImageOrientation(from: connection, devicePosition: devicePosition)

        let result = provider.detectPose(in: sampleBuffer, orientation: orientation)
        onPoseResult?(result)

        onFrameProcessed?()
    }
}
