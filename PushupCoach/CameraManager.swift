import AVFoundation
import UIKit

final class CameraManager: NSObject {
    let session = AVCaptureSession()
    private let processingQueue = DispatchQueue(label: "com.pushupcoach.camera", qos: .userInteractive)
    private var poseProvider: (any PoseProvider)?

    var onPoseResult: ((PoseResult) -> Void)?
    var onFrameProcessed: (() -> Void)?

    func configure(provider: any PoseProvider) {
        self.poseProvider = provider

        session.beginConfiguration()
        session.sessionPreset = .medium

        if let existing = session.inputs.first {
            session.removeInput(existing)
        }
        if let existing = session.outputs.first {
            session.removeOutput(existing)
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
    }

    func switchProvider(_ provider: any PoseProvider) {
        processingQueue.async { [weak self] in
            self?.poseProvider = provider
        }
    }

    func start() {
        processingQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        processingQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let provider = poseProvider else { return }

        if let result = provider.detectPose(in: sampleBuffer) {
            onPoseResult?(result)
        }

        onFrameProcessed?()
    }
}
