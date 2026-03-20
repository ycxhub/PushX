import AVFoundation
import CoreVideo
import UIKit
import ImageIO

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
    func configureAndStart(provider: any PoseProvider, completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?() }
                return
            }

            self.poseProvider = provider

            if self.session.isRunning {
                self.session.stopRunning()
                var spins = 0
                while self.session.isRunning, spins < 200 {
                    Thread.sleep(forTimeInterval: 0.025)
                    spins += 1
                }
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .medium

            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }

            guard let camera = Self.preferredFrontCameraDevice(),
                  let deviceInput = try? AVCaptureDeviceInput(device: camera) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { completion?() }
                return
            }

            guard self.session.canAddInput(deviceInput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { completion?() }
                return
            }
            self.session.addInput(deviceInput)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            ]
            videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)

            guard self.session.canAddOutput(videoOutput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { completion?() }
                return
            }
            self.session.addOutput(videoOutput)

            if let connection = videoOutput.connection(with: .video) {
                CapturePortraitConfiguration.applyPortraitMirroredFrontCamera(to: connection)
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async {
                completion?()
            }
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
