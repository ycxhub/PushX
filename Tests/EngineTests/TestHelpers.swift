import Foundation
import CoreGraphics
import simd
@testable import EngineCore

/// Builds synthetic PoseResult objects for testing engine logic without a camera.
enum SyntheticPose {

    /// A plank/pushup pose as seen from a phone leaning against a wall at floor level.
    ///
    /// Default layout (normalized top-left origin, y-down):
    /// - Shoulders near center (Y ~0.42)
    /// - Nose at or below shoulders (Y ~0.48)  — key plank discriminator
    /// - Elbows and hips close to shoulder level
    /// - Wrists anchored on the floor (defaults to baseline shoulderY when nil)
    ///
    /// Adjust `noseY` to simulate pushup depth (higher Y = deeper).
    /// Set `wristY` explicitly during descent to keep wrists anchored at baseline.
    static func pushupPose(
        noseY: CGFloat = 0.48,
        shoulderLeftX: CGFloat = 0.35,
        shoulderRightX: CGFloat = 0.65,
        shoulderY: CGFloat = 0.42,
        elbowY: CGFloat = 0.50,
        wristY: CGFloat? = nil,
        hipY: CGFloat = 0.48,
        confidence: Float = 0.9,
        noseConfidence: Float? = nil,
        shoulderConfidence: Float? = nil,
        timestamp: TimeInterval = 0,
        shoulderAsymmetryY: CGFloat = 0
    ) -> PoseResult {
        let nc = noseConfidence ?? confidence
        let sc = shoulderConfidence ?? confidence
        let wy = wristY ?? shoulderY

        let landmarks: [Landmark] = [
            Landmark(type: .nose, position: CGPoint(x: 0.5, y: noseY), confidence: nc),
            Landmark(type: .leftEye, position: CGPoint(x: 0.45, y: noseY - 0.02), confidence: confidence),
            Landmark(type: .rightEye, position: CGPoint(x: 0.55, y: noseY - 0.02), confidence: confidence),
            Landmark(type: .leftShoulder, position: CGPoint(x: shoulderLeftX, y: shoulderY), confidence: sc),
            Landmark(type: .rightShoulder, position: CGPoint(x: shoulderRightX, y: shoulderY + shoulderAsymmetryY), confidence: sc),
            Landmark(type: .leftElbow, position: CGPoint(x: 0.25, y: elbowY), confidence: confidence),
            Landmark(type: .rightElbow, position: CGPoint(x: 0.75, y: elbowY), confidence: confidence),
            Landmark(type: .leftWrist, position: CGPoint(x: 0.20, y: wy), confidence: confidence),
            Landmark(type: .rightWrist, position: CGPoint(x: 0.80, y: wy), confidence: confidence),
            Landmark(type: .leftHip, position: CGPoint(x: 0.40, y: hipY), confidence: confidence),
            Landmark(type: .rightHip, position: CGPoint(x: 0.60, y: hipY), confidence: confidence),
        ]

        return PoseResult(landmarks: landmarks, worldLandmarks: nil, timestamp: timestamp)
    }

    /// A standing pose that should NOT pass plank detection.
    ///
    /// Nose well above shoulders, hips far below — classic standing geometry
    /// from a phone at floor level looking up at a standing person.
    static func standingPose(
        noseY: CGFloat = 0.15,
        shoulderY: CGFloat = 0.30,
        hipY: CGFloat = 0.60,
        confidence: Float = 0.9,
        timestamp: TimeInterval = 0
    ) -> PoseResult {
        let landmarks: [Landmark] = [
            Landmark(type: .nose, position: CGPoint(x: 0.5, y: noseY), confidence: confidence),
            Landmark(type: .leftEye, position: CGPoint(x: 0.45, y: noseY - 0.02), confidence: confidence),
            Landmark(type: .rightEye, position: CGPoint(x: 0.55, y: noseY - 0.02), confidence: confidence),
            Landmark(type: .leftShoulder, position: CGPoint(x: 0.35, y: shoulderY), confidence: confidence),
            Landmark(type: .rightShoulder, position: CGPoint(x: 0.65, y: shoulderY), confidence: confidence),
            Landmark(type: .leftElbow, position: CGPoint(x: 0.30, y: shoulderY + 0.08), confidence: confidence),
            Landmark(type: .rightElbow, position: CGPoint(x: 0.70, y: shoulderY + 0.08), confidence: confidence),
            Landmark(type: .leftWrist, position: CGPoint(x: 0.32, y: shoulderY + 0.16), confidence: confidence),
            Landmark(type: .rightWrist, position: CGPoint(x: 0.68, y: shoulderY + 0.16), confidence: confidence),
            Landmark(type: .leftHip, position: CGPoint(x: 0.40, y: hipY), confidence: confidence),
            Landmark(type: .rightHip, position: CGPoint(x: 0.60, y: hipY), confidence: confidence),
        ]

        return PoseResult(landmarks: landmarks, worldLandmarks: nil, timestamp: timestamp)
    }
}
