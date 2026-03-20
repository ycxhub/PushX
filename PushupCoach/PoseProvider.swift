import CoreMedia
import CoreGraphics

enum LandmarkType: String, CaseIterable, Sendable {
    case nose
    case leftEye
    case rightEye
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
}

struct Landmark: Sendable {
    let type: LandmarkType
    let position: CGPoint
    let confidence: Float
}

struct PoseResult: Sendable {
    let landmarks: [Landmark]
    let timestamp: TimeInterval

    func landmark(_ type: LandmarkType) -> Landmark? {
        landmarks.first { $0.type == type }
    }

    var isBodyDetected: Bool {
        let required: [LandmarkType] = [.nose, .leftShoulder, .rightShoulder]
        return required.allSatisfy { type in
            landmarks.contains { $0.type == type && $0.confidence > 0.3 }
        }
    }

    var areKeyLandmarksVisible: Bool {
        let key: [LandmarkType] = [.nose, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow]
        let visible = key.filter { type in
            landmarks.contains { $0.type == type && $0.confidence > 0.5 }
        }
        return visible.count >= 4
    }

    var shoulderSpanNormalized: CGFloat? {
        guard let left = landmark(.leftShoulder),
              let right = landmark(.rightShoulder),
              left.confidence > 0.5 && right.confidence > 0.5 else { return nil }
        return abs(left.position.x - right.position.x)
    }

    var isDistanceOK: Bool {
        guard let span = shoulderSpanNormalized else { return false }
        return span > 0.15 && span < 0.6
    }
}

enum PoseProviderType: String, CaseIterable, Sendable {
    case appleVision = "Apple Vision"
    case mediaPipe = "MediaPipe"
}

protocol PoseProvider: AnyObject {
    var providerType: PoseProviderType { get }
    func detectPose(in sampleBuffer: CMSampleBuffer) -> PoseResult?
}
