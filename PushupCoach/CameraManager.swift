import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import UIKit

enum CameraConfigurationError: Error, LocalizedError {
    case noCameraDevice
    case inputInitializationFailed(String)
    case cannotAddInput
    case cannotAddOutput
    case runtimeError(String)

    var errorDescription: String? {
        switch self {
        case .noCameraDevice:
            return "No front camera is available on this device."
        case .inputInitializationFailed(let detail):
            return "Could not open the camera. \(detail)"
        case .cannotAddInput:
            return "Could not attach the front camera to the capture session."
        case .cannotAddOutput:
            return "Could not start video capture output for the camera session."
        case .runtimeError(let detail):
            return "The camera session failed while starting. \(detail)"
        }
    }
}

final class CameraManager: NSObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.pushupcoach.capture.session", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.pushupcoach.camera", qos: .userInteractive)

    private let providerLock = NSLock()
    private var _poseProvider: (any PoseProvider)?
    private var currentInput: AVCaptureDeviceInput?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var notificationObserversInstalled = false
    private var startupGeneration = UUID()

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

    override init() {
        super.init()
        installLifecycleObservers()
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

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
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }

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

            self.startupGeneration = UUID()
            let generation = self.startupGeneration
            self.poseProvider = provider
            self.emitStartupEvent("startup: entered session queue")
            self.emitStartupEvent("startup: selected provider \(provider.providerType.rawValue)")

            self.stopRunningIfNeeded(reason: "startup: stopping existing session before reconfigure")

            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.medium) {
                self.session.sessionPreset = .medium
            }
            self.emitStartupEvent("startup: began configuration")
            self.removeAllInputsAndOutputs()

            guard let camera = Self.preferredFrontCameraDevice() else {
                self.session.commitConfiguration()
                self.emitStartupEvent("startup failed: no front camera device")
                finish(CameraConfigurationError.noCameraDevice)
                return
            }

            self.emitStartupEvent("startup: resolved camera \(camera.localizedName) type=\(camera.deviceType.rawValue)")

            let deviceInput: AVCaptureDeviceInput
            do {
                deviceInput = try AVCaptureDeviceInput(device: camera)
            } catch {
                self.session.commitConfiguration()
                self.emitStartupEvent("startup failed: input init error \(error.localizedDescription)")
                finish(CameraConfigurationError.inputInitializationFailed(error.localizedDescription))
                return
            }

            guard self.session.canAddInput(deviceInput) else {
                self.session.commitConfiguration()
                self.emitStartupEvent("startup failed: cannot add input")
                finish(CameraConfigurationError.cannotAddInput)
                return
            }
            self.session.addInput(deviceInput)
            self.currentInput = deviceInput
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
            self.installSessionObserversIfNeeded()

            finish(nil)

            self.emitStartupEvent("startup: calling startRunning()")
            self.session.startRunning()
            let isCurrentGeneration = generation == self.startupGeneration
            self.emitStartupEvent("startup: startRunning() returned (isRunning=\(self.session.isRunning)) generationCurrent=\(isCurrentGeneration)")
            if !self.session.isRunning {
                finish(CameraConfigurationError.runtimeError("The session returned from startRunning without entering a running state."))
            }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?() }
                return
            }
            self.stopRunningIfNeeded(reason: "stop: requested")
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    func resetAndStop(completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?() }
                return
            }
            self.emitStartupEvent("recovery: resetting capture session")
            self.startupGeneration = UUID()
            self.stopRunningIfNeeded(reason: "recovery: stop session")
            self.session.beginConfiguration()
            self.removeAllInputsAndOutputs()
            self.session.commitConfiguration()
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

    private func removeAllInputsAndOutputs() {
        for input in session.inputs {
            session.removeInput(input)
        }
        currentInput = nil
        for output in session.outputs {
            session.removeOutput(output)
        }
        emitStartupEvent("startup: cleared previous inputs and outputs")
    }

    private func stopRunningIfNeeded(reason: String) {
        emitStartupEvent(reason)
        if session.isRunning {
            session.stopRunning()
            var spins = 0
            while session.isRunning, spins < 200 {
                Thread.sleep(forTimeInterval: 0.025)
                spins += 1
            }
            emitStartupEvent("session: stopRunning complete (isRunning=\(session.isRunning))")
        }
    }

    private func installLifecycleObservers() {
        let center = NotificationCenter.default
        lifecycleObservers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.emitStartupEvent("app: didEnterBackground")
            }
        )
        lifecycleObservers.append(
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.emitStartupEvent("app: willEnterForeground")
            }
        )
    }

    private func installSessionObserversIfNeeded() {
        guard !notificationObserversInstalled else { return }
        notificationObserversInstalled = true
        let center = NotificationCenter.default

        lifecycleObservers.append(
            center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] note in
                let rawReason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
                self?.emitStartupEvent("session interrupted reason=\(rawReason.map(String.init) ?? "unknown")")
            }
        )

        lifecycleObservers.append(
            center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
                self?.emitStartupEvent("session interruption ended")
            }
        )

        lifecycleObservers.append(
            center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                self?.emitStartupEvent("session runtime error code=\(error?.code ?? -1) domain=\(error?.domain ?? "unknown") message=\(error?.localizedDescription ?? "unknown")")
            }
        )
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
