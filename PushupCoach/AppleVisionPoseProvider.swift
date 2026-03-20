import Vision
import CoreMedia
import CoreGraphics
import ImageIO

/// Human-body pose from Apple Vision. Joint names are **image left / image right** in the buffer passed
/// to `VNImageRequestHandler`. We use the same mirrored front-camera connection as the preview, so labels
/// match what the user sees. **Shoulder alignment scoring** that uses `abs(leftY − rightY)` is unchanged if
/// left/right were swapped (symmetric metric); avoid **single-sided** cues unless you account for mirror semantics.
final class AppleVisionPoseProvider: PoseProvider {
    let providerType: PoseProviderType = .appleVision

    /// Create a fresh request per frame. `VNRequest` is not safe to share across concurrent
    /// `VNImageRequestHandler.perform` calls from the camera queue.
    private static let jointMapping: [VNHumanBodyPoseObservation.JointName: LandmarkType] = [
        .nose: .nose,
        .leftEye: .leftEye,
        .rightEye: .rightEye,
        .leftShoulder: .leftShoulder,
        .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow,
        .rightElbow: .rightElbow,
        .leftWrist: .leftWrist,
        .rightWrist: .rightWrist,
        .leftHip: .leftHip,
        .rightHip: .rightHip,
    ]

    private static let scoringJoints: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftHip, .rightHip,
    ]

    func detectPose(in sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> PoseResult? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        let observation = pickBestObservation(from: observations)

        var landmarks: [Landmark] = []

        for (jointName, landmarkType) in Self.jointMapping {
            guard let point = try? observation.recognizedPoint(jointName) else { continue }
            let topLeft = CGPoint(x: point.location.x, y: 1.0 - point.location.y)
            landmarks.append(Landmark(type: landmarkType, position: topLeft, confidence: point.confidence))
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        return PoseResult(landmarks: landmarks, worldLandmarks: nil, timestamp: timestamp)
    }

    private func pickBestObservation(from observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation {
        var best = observations[0]
        var bestScore: Float = -1

        for obs in observations {
            var score: Float = 0
            for joint in Self.scoringJoints {
                if let p = try? obs.recognizedPoint(joint) {
                    score += p.confidence
                }
            }
            if score > bestScore {
                bestScore = score
                best = obs
            }
        }
        return best
    }
}
