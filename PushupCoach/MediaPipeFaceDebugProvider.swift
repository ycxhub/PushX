import MediaPipeTasksVision
import CoreMedia
import CoreGraphics
import UIKit

/// Runs MediaPipe Face Landmarker on camera frames (video mode) for orientation QA while seated.
final class MediaPipeFaceDebugProvider {
    private var faceLandmarker: FaceLandmarker?

    init() {
        guard let modelPath = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
            print("[MediaPipeFaceDebugProvider] face_landmarker.task not found in bundle")
            return
        }

        let options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .video
        options.numFaces = 1
        options.minFaceDetectionConfidence = 0.25
        options.minFacePresenceConfidence = 0.25
        options.minTrackingConfidence = 0.25

        do {
            faceLandmarker = try FaceLandmarker(options: options)
        } catch {
            print("[MediaPipeFaceDebugProvider] Failed to create FaceLandmarker: \(error)")
        }
    }

    /// Normalized image coordinates (origin top-left, x right, y down), first face only — in **display** orientation.
    func normalizedLandmarks(from sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation) -> [CGPoint] {
        guard let landmarker = faceLandmarker else { return [] }

        let mpImage: MPImage
        do {
            mpImage = try MPImage(sampleBuffer: sampleBuffer, orientation: orientation)
        } catch {
            return []
        }

        let timestampMs = Int(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds * 1000)

        let result: FaceLandmarkerResult
        do {
            result = try landmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
        } catch {
            return []
        }

        guard let face = result.faceLandmarks.first else { return [] }

        return face.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    }
}
