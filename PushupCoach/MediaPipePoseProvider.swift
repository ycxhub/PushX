import MediaPipeTasksVision
import CoreMedia
import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// BlazePose via MediaPipe Tasks (`pose_landmarker_full.task` in the app bundle).
/// **Default model:** full — best accuracy/latency tradeoff for Phase 0; swap the `.task` asset for
/// `pose_landmarker_lite` or `pose_landmarker_heavy` from Google’s MediaPipe Tasks iOS pack if you need speed or max quality.
///
/// `PoseLandmarker` is created lazily on the **first** `detectPose` call (the camera delegate queue), not in `init`.
/// Eager init on the main actor blocked the UI for a long time (Metal) while the start button waited on `configureAndStart`.
final class MediaPipePoseProvider: PoseProvider {
    let providerType: PoseProviderType = .mediaPipe

    private let landmarkerLock = NSLock()
    private var poseLandmarker: PoseLandmarker?
    private var landmarkerSetupFailed = false

    /// MediaPipe's 33-landmark indices mapped to our LandmarkType.
    private static let indexToType: [Int: LandmarkType] = [
        0:  .nose,
        1:  .leftEyeInner,
        2:  .leftEye,
        3:  .leftEyeOuter,
        4:  .rightEyeInner,
        5:  .rightEye,
        6:  .rightEyeOuter,
        7:  .leftEar,
        8:  .rightEar,
        9:  .mouthLeft,
        10: .mouthRight,
        11: .leftShoulder,
        12: .rightShoulder,
        13: .leftElbow,
        14: .rightElbow,
        15: .leftWrist,
        16: .rightWrist,
        17: .leftPinky,
        18: .rightPinky,
        19: .leftIndex,
        20: .rightIndex,
        21: .leftThumb,
        22: .rightThumb,
        23: .leftHip,
        24: .rightHip,
        25: .leftKnee,
        26: .rightKnee,
        27: .leftAnkle,
        28: .rightAnkle,
        29: .leftHeel,
        30: .rightHeel,
        31: .leftFootIndex,
        32: .rightFootIndex,
    ]

    init() {}

    /// Thread-safe one-shot setup; runs on the camera sample-buffer queue (not the main actor).
    private func ensureLandmarker() -> Bool {
        if poseLandmarker != nil { return true }
        if landmarkerSetupFailed { return false }

        landmarkerLock.lock()
        defer { landmarkerLock.unlock() }

        if poseLandmarker != nil { return true }
        if landmarkerSetupFailed { return false }

        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") else {
            print("[MediaPipePoseProvider] Model file not found in bundle")
            landmarkerSetupFailed = true
            return false
        }

        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .video
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.25
        options.minPosePresenceConfidence = 0.25
        options.minTrackingConfidence = 0.25

        do {
            poseLandmarker = try PoseLandmarker(options: options)
            return true
        } catch {
            landmarkerSetupFailed = true
            print("[MediaPipePoseProvider] Failed to create PoseLandmarker: \(error)")
            return false
        }
    }

    func detectPose(in sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> PoseResult? {
        guard ensureLandmarker(), let landmarker = poseLandmarker else { return nil }

        let mpOrientation = orientation.uiImageOrientation
        let mpImage: MPImage
        do {
            mpImage = try MPImage(sampleBuffer: sampleBuffer, orientation: mpOrientation)
        } catch {
            return nil
        }

        let timestampMs = Int(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds * 1000)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        let result: PoseLandmarkerResult
        do {
            result = try landmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
        } catch {
            return nil
        }

        guard let firstPoseLandmarks = result.landmarks.first,
              !firstPoseLandmarks.isEmpty else {
            return nil
        }

        var landmarks2D: [Landmark] = []
        for (index, normalized) in firstPoseLandmarks.enumerated() {
            guard let type = Self.indexToType[index] else { continue }
            let confidence = normalized.visibility?.floatValue ?? normalized.presence?.floatValue ?? 0.5
            let point = CGPoint(x: CGFloat(normalized.x), y: CGFloat(normalized.y))
            landmarks2D.append(Landmark(type: type, position: point, confidence: confidence))
        }

        var landmarks3D: [Landmark3D]? = nil
        if let firstWorldLandmarks = result.worldLandmarks.first, !firstWorldLandmarks.isEmpty {
            var world: [Landmark3D] = []
            for (index, wl) in firstWorldLandmarks.enumerated() {
                guard let type = Self.indexToType[index] else { continue }
                let confidence = wl.visibility?.floatValue ?? wl.presence?.floatValue ?? 0.5
                let pos = SIMD3<Float>(wl.x, wl.y, wl.z)
                world.append(Landmark3D(type: type, position: pos, confidence: confidence))
            }
            landmarks3D = world
        }

        return PoseResult(landmarks: landmarks2D, worldLandmarks: landmarks3D, timestamp: timestamp)
    }
}
