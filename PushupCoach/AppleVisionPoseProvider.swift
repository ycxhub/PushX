import Vision
import CoreMedia

final class AppleVisionPoseProvider: PoseProvider {
    let providerType: PoseProviderType = .appleVision

    private let request = VNDetectHumanBodyPoseRequest()

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

    func detectPose(in sampleBuffer: CMSampleBuffer) -> PoseResult? {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else {
            return nil
        }

        var landmarks: [Landmark] = []

        for (jointName, landmarkType) in Self.jointMapping {
            guard let point = try? observation.recognizedPoint(jointName) else { continue }
            // Vision returns coordinates with origin at bottom-left, Y going up.
            // Convert to top-left origin (standard screen coordinates).
            let screenPoint = CGPoint(x: point.location.x, y: 1.0 - point.location.y)
            landmarks.append(Landmark(type: landmarkType, position: screenPoint, confidence: point.confidence))
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        return PoseResult(landmarks: landmarks, timestamp: timestamp)
    }
}
