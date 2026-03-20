import AVFoundation
import CoreVideo
import UIKit

/// Separate capture session for face landmarker QA only (does not run pose).
final class FaceDebugCameraManager: NSObject {
    let session = AVCaptureSession()
    private let processingQueue = DispatchQueue(label: "com.pushupcoach.face.debug", qos: .userInteractive)
    /// Lazily created so opening the main app doesn’t load the face model until the face QA screen runs `configure()`.
    private lazy var faceProvider = MediaPipeFaceDebugProvider()
    private let devicePosition: AVCaptureDevice.Position = .front

    /// Normalized top-left landmarks for the first face; empty if none.
    var onLandmarks: (([CGPoint]) -> Void)?

    func configure() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        if let existing = session.inputs.first {
            session.removeInput(existing)
        }
        if let existing = session.outputs.first {
            session.removeOutput(existing)
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: devicePosition),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        ]
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            CapturePortraitConfiguration.applyPortraitMirroredFrontCamera(to: connection)
        }

        session.commitConfiguration()
    }

    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

extension FaceDebugCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let uiOrientation = VisionOrientation.uiImageOrientation(from: connection, devicePosition: devicePosition)
        let points = faceProvider.normalizedLandmarks(from: sampleBuffer, orientation: uiOrientation)
        DispatchQueue.main.async { [weak self] in
            self?.onLandmarks?(points)
        }
    }
}
