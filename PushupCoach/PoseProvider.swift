import CoreMedia
import CoreGraphics
import ImageIO
import simd

enum LandmarkType: String, CaseIterable, Sendable {
    // Upper body (supported by both Apple Vision and MediaPipe)
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

    // Lower body + extremities (MediaPipe only — 33-point model)
    case leftEyeInner
    case leftEyeOuter
    case rightEyeInner
    case rightEyeOuter
    case leftEar
    case rightEar
    case leftPinky
    case rightPinky
    case leftIndex
    case rightIndex
    case leftThumb
    case rightThumb
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
    case leftHeel
    case rightHeel
    case leftFootIndex
    case rightFootIndex
    case mouthLeft
    case mouthRight

    /// Landmarks available from Apple Vision's 19-point body pose model.
    static let appleVisionSet: Set<LandmarkType> = [
        .nose, .leftEye, .rightEye,
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
        .leftHip, .rightHip,
    ]
}

struct Landmark: Sendable {
    let type: LandmarkType
    let position: CGPoint
    let confidence: Float
}

struct Landmark3D: Sendable {
    let type: LandmarkType
    /// World coordinates in meters. Origin at hip center; y points down, z toward camera.
    let position: SIMD3<Float>
    let confidence: Float
}

/// Normalized 2D coordinates: origin **top-left**, x right, y down, range [0,1].
/// Optional `worldLandmarks` populated by MediaPipe with 3D coordinates in meters.
struct PoseResult: Sendable {
    let landmarks: [Landmark]
    let worldLandmarks: [Landmark3D]?
    let timestamp: TimeInterval

    func landmark(_ type: LandmarkType) -> Landmark? {
        landmarks.first { $0.type == type }
    }

    func worldLandmark(_ type: LandmarkType) -> Landmark3D? {
        worldLandmarks?.first { $0.type == type }
    }

    var hasAnybodyPresent: Bool {
        landmarks.contains { $0.confidence > 0.15 }
    }

    /// Nose + at least ONE shoulder at moderate confidence.
    var hasCoreLandmarksForTracking: Bool {
        guard let nose = landmark(.nose), nose.confidence >= 0.25 else { return false }
        let ls = landmark(.leftShoulder)
        let rs = landmark(.rightShoulder)
        let leftOK = (ls?.confidence ?? 0) >= 0.2
        let rightOK = (rs?.confidence ?? 0) >= 0.2
        return leftOK || rightOK
    }

    var isBodyDetected: Bool {
        hasCoreLandmarksForTracking
    }

    /// Strong enough core keypoints to drive the **rep state machine** (blocks wall hallucinations).
    var isRepCountingQualityPose: Bool {
        guard let nose = landmark(.nose), nose.confidence >= 0.5 else { return false }
        guard let ls = landmark(.leftShoulder), let rs = landmark(.rightShoulder),
              ls.confidence >= 0.38, rs.confidence >= 0.38 else { return false }
        return true
    }

    var isCalibratedForPushup: Bool {
        guard hasCoreLandmarksForTracking else { return false }
        guard isDistanceOK else { return false }
        guard hasArmExtensionHintForCalibration else { return false }
        return true
    }

    /// Core landmarks plus a visible arm hint at checklist threshold (UI dots).
    var areKeyLandmarksVisible: Bool {
        guard hasCoreLandmarksForTracking else { return false }
        return hasArmExtensionHintForChecklist
    }

    /// Calibration / rep arming — stricter elbow–wrist visibility.
    var hasArmExtensionHintForCalibration: Bool {
        armHint(types: [.leftElbow, .rightElbow, .leftWrist, .rightWrist], minConfidence: PushupPoseConstants.armHintConfidenceCalibration)
    }

    /// Checklist — softer threshold for plank frames.
    var hasArmExtensionHintForChecklist: Bool {
        armHint(types: [.leftElbow, .rightElbow, .leftWrist, .rightWrist], minConfidence: PushupPoseConstants.armHintConfidenceChecklist)
    }

    private func armHint(types: [LandmarkType], minConfidence: Float) -> Bool {
        types.contains { t in
            guard let p = landmark(t) else { return false }
            return p.confidence >= minConfidence
        }
    }

    /// Horizontal shoulder separation (face-on pushup — primary distance metric).
    var shoulderSeparationX: CGFloat? {
        guard let left = landmark(.leftShoulder),
              let right = landmark(.rightShoulder),
              left.confidence > 0.15 && right.confidence > 0.15 else { return nil }
        return abs(left.position.x - right.position.x)
    }

    /// Legacy: max(Δx, Δy) between shoulders.
    var shoulderSpanNormalized: CGFloat? {
        guard let left = landmark(.leftShoulder),
              let right = landmark(.rightShoulder),
              left.confidence > 0.15 && right.confidence > 0.15 else { return nil }
        let dx = abs(left.position.x - right.position.x)
        let dy = abs(left.position.y - right.position.y)
        return max(dx, dy)
    }

    /// Distance metric: prefer horizontal span for calibration / feedback; fallback to max(dx,dy).
    var shoulderSpanForCalibrationMetric: CGFloat? {
        if let sx = shoulderSeparationX, sx >= 0.02 { return sx }
        return shoulderSpanNormalized
    }

    /// Calibration distance band (stricter).
    var isDistanceOK: Bool {
        guard let span = shoulderSpanForCalibrationMetric else { return false }
        return span >= PushupPoseConstants.shoulderSpanCalibrateMin && span <= PushupPoseConstants.shoulderSpanCalibrateMax
    }

    /// Pre-lock gate band (looser).
    var hasShoulderSpanInTrackingBand: Bool {
        guard let span = shoulderSpanForCalibrationMetric else { return false }
        return span >= PushupPoseConstants.shoulderSpanGateMin && span <= PushupPoseConstants.shoulderSpanGateMax
    }

    /// Trunk horizontal enough when the body is side-on in the image (weak for pure face-on plank).
    var isTrunkAngleReadyForPushup: Bool {
        guard let angle = trunkAngleFromVertical else { return false }
        return angle >= PushupPoseConstants.minTrunkAngleForPushup
    }

    /// Face-on plank: elbows typically **below** shoulders in image space (y-down); optional world-space cue.
    var isPlankLikeForFaceOnCamera: Bool {
        if plankLikelihoodWorld { return true }
        return plankLikelihood2D
    }

    private var plankLikelihoodWorld: Bool {
        guard let wls = worldLandmark(.leftShoulder), let wrs = worldLandmark(.rightShoulder),
              let wlh = worldLandmark(.leftHip), let wrh = worldLandmark(.rightHip),
              wls.confidence > 0.25, wrs.confidence > 0.25, wlh.confidence > 0.25, wrh.confidence > 0.25 else {
            return false
        }
        let shoulderY = (wls.position.y + wrs.position.y) * 0.5
        let hipY = (wlh.position.y + wrh.position.y) * 0.5
        // Hips “below” shoulders in world (y down) in plank facing camera.
        return (hipY - shoulderY) > 0.035
    }

    private var plankLikelihood2D: Bool {
        guard let ls = landmark(.leftShoulder), let rs = landmark(.rightShoulder),
              ls.confidence > 0.22, rs.confidence > 0.22 else { return false }
        let shoulderMidY = (ls.position.y + rs.position.y) * 0.5

        var elbowBelow = 0
        var elbowChecked = 0
        if let le = landmark(.leftElbow), le.confidence > 0.22 {
            elbowChecked += 1
            if le.position.y > shoulderMidY + 0.015 { elbowBelow += 1 }
        }
        if let re = landmark(.rightElbow), re.confidence > 0.22 {
            elbowChecked += 1
            if re.position.y > shoulderMidY + 0.015 { elbowBelow += 1 }
        }

        if elbowChecked >= 1, elbowBelow >= 1 { return true }

        if let nose = landmark(.nose), nose.confidence > 0.3,
           let lh = landmark(.leftHip), let rh = landmark(.rightHip),
           lh.confidence > 0.2, rh.confidence > 0.2 {
            let hipMidY = (lh.position.y + rh.position.y) * 0.5
            if nose.position.y > shoulderMidY - 0.04, hipMidY > shoulderMidY + 0.02 {
                return true
            }
        }

        return false
    }

    /// Ready to arm reps from idle: calibration + (side-on trunk **or** face-on plank).
    var isPostureReadyForRepCounting: Bool {
        isCalibratedForPushup && (isTrunkAngleReadyForPushup || isPlankLikeForFaceOnCamera)
    }

    /// Live shoulder imbalance for HUD (meters in world space when available, else normalized 2D).
    var shoulderVerticalDelta: CGFloat? {
        if let wl = worldLandmark(.leftShoulder), let wr = worldLandmark(.rightShoulder),
           wl.confidence >= 0.25, wr.confidence >= 0.25 {
            return abs(CGFloat(wl.position.y - wr.position.y))
        }
        guard let ls = landmark(.leftShoulder), let rs = landmark(.rightShoulder),
              ls.confidence >= 0.25, rs.confidence >= 0.25 else { return nil }
        return abs(ls.position.y - rs.position.y)
    }

    /// Bounding box of all landmarks with confidence above threshold, in normalized [0,1] coords.
    func boundingBox(minConfidence: Float = 0.15) -> CGRect? {
        let visible = landmarks.filter { $0.confidence >= minConfidence }
        guard !visible.isEmpty else { return nil }
        var minX: CGFloat = 1, minY: CGFloat = 1, maxX: CGFloat = 0, maxY: CGFloat = 0
        for lm in visible {
            minX = min(minX, lm.position.x)
            minY = min(minY, lm.position.y)
            maxX = max(maxX, lm.position.x)
            maxY = max(maxY, lm.position.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Angle of the body's trunk from vertical (0 = upright, 90 = horizontal).
    /// Uses midpoint of shoulders vs midpoint of hips.
    var trunkAngleFromVertical: CGFloat? {
        guard let ls = landmark(.leftShoulder), let rs = landmark(.rightShoulder),
              let lh = landmark(.leftHip), let rh = landmark(.rightHip),
              ls.confidence > 0.15 && rs.confidence > 0.15 &&
              lh.confidence > 0.15 && rh.confidence > 0.15 else { return nil }
        let shoulderMid = CGPoint(x: (ls.position.x + rs.position.x) / 2,
                                  y: (ls.position.y + rs.position.y) / 2)
        let hipMid = CGPoint(x: (lh.position.x + rh.position.x) / 2,
                             y: (lh.position.y + rh.position.y) / 2)
        let dx = hipMid.x - shoulderMid.x
        let dy = hipMid.y - shoulderMid.y
        let angle = atan2(abs(dx), abs(dy)) * 180 / .pi
        return angle
    }
}

enum PoseProviderType: String, CaseIterable, Sendable {
    case appleVision = "Apple Vision"
    case mediaPipe = "MediaPipe"
}

protocol PoseProvider: AnyObject {
    var providerType: PoseProviderType { get }
    func detectPose(in sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> PoseResult?
}
