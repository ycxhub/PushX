import CoreMedia
import CoreGraphics
import ImageIO
import simd

enum DistanceAssessment: String, Sendable, Codable {
    case unavailable
    case tooClose
    case tooFar
    case usable
    case ideal
}

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

    private static let headLandmarkTypes: [LandmarkType] = [
        .nose,
        .leftEye, .rightEye,
        .leftEyeInner, .leftEyeOuter,
        .rightEyeInner, .rightEyeOuter,
        .leftEar, .rightEar,
        .mouthLeft, .mouthRight,
    ]

    private var visibleHeadLandmarks: [Landmark] {
        Self.headLandmarkTypes.compactMap(landmark).filter { $0.confidence >= 0.18 }
    }

    /// Stable head/neck proxy used for gating and rep tracking. This deliberately does not rely on the
    /// nose alone because users frequently look at the phone during the first rep.
    var headReferenceY: CGFloat? {
        let visible = visibleHeadLandmarks
        guard !visible.isEmpty else { return nil }
        let sorted = visible.map(\.position.y).sorted()
        return sorted[sorted.count / 2]
    }

    var headVisibilityScore: Double {
        let visible = visibleHeadLandmarks
        guard !visible.isEmpty else { return 0 }
        let total = visible.reduce(0.0) { $0 + Double($1.confidence) }
        return total / Double(visible.count)
    }

    var hasRepCountingAnchorLandmarks: Bool {
        let leftShoulder = landmark(.leftShoulder)?.confidence ?? 0
        let rightShoulder = landmark(.rightShoulder)?.confidence ?? 0
        guard leftShoulder >= 0.24 || rightShoulder >= 0.24 else { return false }

        let armVisible: Bool = [.leftElbow, .rightElbow, .leftWrist, .rightWrist].contains {
            (landmark($0)?.confidence ?? 0) >= 0.18
        }
        let hipsVisible = (landmark(.leftHip)?.confidence ?? 0) >= 0.18 || (landmark(.rightHip)?.confidence ?? 0) >= 0.18
        return armVisible || hipsVisible || headReferenceY != nil
    }

    /// Nose + at least ONE shoulder at moderate confidence.
    var hasCoreLandmarksForTracking: Bool {
        let ls = landmark(.leftShoulder)
        let rs = landmark(.rightShoulder)
        let leftOK = (ls?.confidence ?? 0) >= 0.2
        let rightOK = (rs?.confidence ?? 0) >= 0.2
        guard leftOK || rightOK else { return false }
        return headReferenceY != nil || hasRepCountingAnchorLandmarks
    }

    var isBodyDetected: Bool {
        hasCoreLandmarksForTracking
    }

    var shoulderMidYForTracking: CGFloat? {
        guard let left = landmark(.leftShoulder),
              let right = landmark(.rightShoulder),
              left.confidence >= 0.18,
              right.confidence >= 0.18 else { return nil }
        return (left.position.y + right.position.y) * 0.5
    }

    var hipMidYForTracking: CGFloat? {
        guard let left = landmark(.leftHip),
              let right = landmark(.rightHip),
              left.confidence >= 0.16,
              right.confidence >= 0.16 else { return nil }
        return (left.position.y + right.position.y) * 0.5
    }

    /// Strong enough core keypoints to drive the **rep state machine** (blocks wall hallucinations).
    var isRepCountingQualityPose: Bool {
        guard let ls = landmark(.leftShoulder), let rs = landmark(.rightShoulder),
              ls.confidence >= 0.32, rs.confidence >= 0.32 else { return false }
        let elbowsOrWristsVisible =
            (landmark(.leftElbow)?.confidence ?? 0) >= 0.16 ||
            (landmark(.rightElbow)?.confidence ?? 0) >= 0.16 ||
            (landmark(.leftWrist)?.confidence ?? 0) >= 0.16 ||
            (landmark(.rightWrist)?.confidence ?? 0) >= 0.16
        let hipsVisible =
            (landmark(.leftHip)?.confidence ?? 0) >= 0.16 &&
            (landmark(.rightHip)?.confidence ?? 0) >= 0.16
        return headReferenceY != nil || elbowsOrWristsVisible || hipsVisible
    }

    var isCalibratedForPushup: Bool {
        guard hasCoreLandmarksForTracking else { return false }
        guard distanceAssessment == .ideal || distanceAssessment == .usable else { return false }
        guard hasArmExtensionHintForCalibration || hasRepCountingAnchorLandmarks else { return false }
        return isPushupLikeBodyOrientation
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
        distanceAssessment == .ideal
    }

    /// Pre-lock gate band (looser).
    var hasShoulderSpanInTrackingBand: Bool {
        guard let span = shoulderSpanForCalibrationMetric else { return false }
        return span >= PushupPoseConstants.shoulderSpanGateMin && span <= PushupPoseConstants.shoulderSpanGateMax
    }

    var distanceAssessment: DistanceAssessment {
        guard let span = shoulderSpanForCalibrationMetric else { return .unavailable }
        if span < PushupPoseConstants.shoulderSpanUsableMin { return .tooFar }
        if span > PushupPoseConstants.shoulderSpanUsableMax { return .tooClose }
        if span < PushupPoseConstants.shoulderSpanCalibrateMin || span > PushupPoseConstants.shoulderSpanCalibrateMax {
            return .usable
        }
        return .ideal
    }

    var isPushupLikeBodyOrientation: Bool {
        guard !isStandingPose else { return false }
        guard let trunkAngle = trunkAngleFromVertical,
              trunkAngle >= PushupPoseConstants.minTrunkAngleForPushup else { return false }

        guard let ls = landmark(.leftShoulder), let rs = landmark(.rightShoulder),
              ls.confidence >= 0.2, rs.confidence >= 0.2 else { return false }
        let shoulderMidY = (ls.position.y + rs.position.y) * 0.5

        if let lh = landmark(.leftHip), let rh = landmark(.rightHip),
           lh.confidence >= 0.18, rh.confidence >= 0.18 {
            let hipMidY = (lh.position.y + rh.position.y) * 0.5
            if hipMidY > shoulderMidY + 0.22 {
                return false
            }
        }

        if let headY = headReferenceY, headY < shoulderMidY - 0.14 {
            return false
        }

        return true
    }

    /// Phone-against-wall plank detection.
    ///
    /// Camera is at floor level looking horizontally at the user. In plank/pushup position the head
    /// hangs between or below the shoulders so `nose.y >= shoulderMidY` (y-down). When standing the
    /// nose is well above the shoulders and hips are far below — both rejected here.
    var isInPlankFromFrontCamera: Bool {
        guard isPushupLikeBodyOrientation else { return false }
        guard let ls = landmark(.leftShoulder), let rs = landmark(.rightShoulder),
              ls.confidence >= 0.25, rs.confidence >= 0.25 else { return false }

        let shoulderMidY = (ls.position.y + rs.position.y) * 0.5
        if let headY = headReferenceY {
            return headY >= shoulderMidY - 0.12
        }
        return hasRepCountingAnchorLandmarks
    }

    /// Explicit standing rejection — hips far below shoulders with nose above them.
    var isStandingPose: Bool {
        guard let nose = landmark(.nose), nose.confidence >= 0.3,
              let ls = landmark(.leftShoulder), let rs = landmark(.rightShoulder),
              ls.confidence >= 0.25, rs.confidence >= 0.25,
              let lh = landmark(.leftHip), let rh = landmark(.rightHip),
              lh.confidence >= 0.25, rh.confidence >= 0.25 else { return false }

        let shoulderMidY = (ls.position.y + rs.position.y) * 0.5
        let hipMidY = (lh.position.y + rh.position.y) * 0.5

        let hipsWellBelowShoulders = (hipMidY - shoulderMidY) > 0.15
        let noseAboveShoulders = nose.position.y < shoulderMidY
        return hipsWellBelowShoulders && noseAboveShoulders
    }

    /// Ready to arm reps from idle: calibration checks pass and user is in plank position.
    var isPostureReadyForRepCounting: Bool {
        hasRepCountingAnchorLandmarks && isInPlankFromFrontCamera && (distanceAssessment == .ideal || distanceAssessment == .usable)
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

    var publicFacingName: String {
        switch self {
        case .appleVision:
            return "PushXPose"
        case .mediaPipe:
            return "PushXPose"
        }
    }
}

protocol PoseProvider: AnyObject {
    var providerType: PoseProviderType { get }
    func detectPose(in sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> PoseResult?
}
