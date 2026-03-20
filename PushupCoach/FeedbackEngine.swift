import Foundation
import CoreGraphics

enum FeedbackLayer: Int, Comparable {
    case insideBox = 0
    /// Soft distance / framing (shoulder span) — before trunk angle.
    case bodyDistance = 1
    case bodyPosition = 2
    case jointVisibility = 3
    case exerciseRule = 4

    static func < (lhs: FeedbackLayer, rhs: FeedbackLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct FeedbackItem {
    let layer: FeedbackLayer
    let message: String
    /// When true, skeleton overlay should be hidden as a strong visual signal.
    let isRequired: Bool
}

struct FeedbackResult {
    /// Highest-priority active feedback, or nil if everything passes.
    let topFeedback: FeedbackItem?
    /// All active feedback items sorted by priority (lowest layer index first).
    let allFeedback: [FeedbackItem]

    var shouldHideSkeleton: Bool {
        topFeedback?.isRequired == true
    }

    var message: String {
        topFeedback?.message ?? ""
    }

    /// Next coaching line when multiple issues exist (e.g. required top + soft secondary).
    var secondaryCoachingMessage: String? {
        let items = allFeedback
        guard items.count > 1 else { return nil }
        if let top = items.first, top.isRequired {
            return items.dropFirst().first(where: { !$0.isRequired })?.message ?? items[1].message
        }
        return items[1].message
    }
}

/// Evaluates pose quality across 4 priority layers. Runs every frame while tracking is locked.
///
/// Layer 1 – Inside Box: body bounding box within the safe area of the frame
/// Layer 2 – Body Position: body orientation roughly horizontal (pushup position)
/// Layer 3 – Joint Visibility: critical joints above minimum confidence
/// Layer 4 – Exercise Rule: form corrections during the exercise
final class FeedbackEngine {

    private var hipSagFrames = 0
    private let hipSagFrameThreshold = 8
    private var kneeBentFrames = 0
    private let kneeBentFrameThreshold = 8

    /// Minimum confidence for a joint to count as "visible."
    private let jointVisibilityThreshold: Float = 0.25

    /// Critical joints that must be visible for proper pushup tracking.
    private let criticalJoints: [(type: LandmarkType, label: String)] = [
        (.leftShoulder, "left arm"),
        (.rightShoulder, "right arm"),
        (.leftElbow, "left arm"),
        (.rightElbow, "right arm"),
        (.leftHip, "left hip"),
        (.rightHip, "right hip"),
    ]

    func evaluate(pose: PoseResult, isExercising: Bool) -> FeedbackResult {
        var items: [FeedbackItem] = []

        // ---- Layer 1: Inside Box ----
        if let boxItem = checkInsideBox(pose) {
            items.append(boxItem)
        }

        // ---- Layer 2a: Distance (shoulder span band) — soft cue ----
        if let dist = checkShoulderDistance(pose) {
            items.append(dist)
        }

        // ---- Layer 2b: Body Position (plank / trunk) ----
        if let posItem = checkBodyPosition(pose) {
            items.append(posItem)
        }

        // ---- Layer 3: Joint Visibility ----
        items.append(contentsOf: checkJointVisibility(pose))

        // ---- Layer 4: Exercise Rule (only during active exercise) ----
        if isExercising {
            items.append(contentsOf: checkExerciseRules(pose))
        }

        items.sort { $0.layer < $1.layer }
        let top = items.first
        return FeedbackResult(topFeedback: top, allFeedback: items)
    }

    func reset() {
        hipSagFrames = 0
        kneeBentFrames = 0
    }

    // MARK: - Layer 1: Inside Box

    private func checkInsideBox(_ pose: PoseResult) -> FeedbackItem? {
        let inset = PushupPoseConstants.safeFrameInset
        guard let bbox = pose.boundingBox(minConfidence: 0.15) else { return nil }
        let tooLeft = bbox.minX < inset
        let tooRight = bbox.maxX > (1 - inset)
        let tooHigh = bbox.minY < inset
        let tooLow = bbox.maxY > (1 - inset)

        if tooLeft || tooRight || tooHigh || tooLow {
            var direction = ""
            if tooLeft { direction = "right" }
            else if tooRight { direction = "left" }
            else if tooHigh { direction = "down" }
            else if tooLow { direction = "up" }
            return FeedbackItem(
                layer: .insideBox,
                message: "Move whole body into the box — shift \(direction)",
                isRequired: true
            )
        }
        return nil
    }

    // MARK: - Layer 2a: Shoulder distance

    private func checkShoulderDistance(_ pose: PoseResult) -> FeedbackItem? {
        guard let span = pose.shoulderSpanForCalibrationMetric else {
            return FeedbackItem(
                layer: .bodyDistance,
                message: "Get your upper body in frame so we can see both shoulders",
                isRequired: false
            )
        }
        // Small normalized span with phone on floor usually means user is **too far** (tiny shoulders).
        if span < PushupPoseConstants.shoulderSpanCalibrateMin {
            return FeedbackItem(
                layer: .bodyDistance,
                message: "Come closer — fill more of the frame with your upper body",
                isRequired: false
            )
        }
        if span > PushupPoseConstants.shoulderSpanCalibrateMax {
            return FeedbackItem(
                layer: .bodyDistance,
                message: "Move back slightly — give yourself more room in frame",
                isRequired: false
            )
        }
        return nil
    }

    // MARK: - Layer 2b: Body Position

    private func checkBodyPosition(_ pose: PoseResult) -> FeedbackItem? {
        if pose.isTrunkAngleReadyForPushup || pose.isPlankLikeForFaceOnCamera {
            return nil
        }
        return FeedbackItem(
            layer: .bodyPosition,
            message: "Get on your front, facing the camera",
            isRequired: true
        )
    }

    // MARK: - Layer 3: Joint Visibility

    private func checkJointVisibility(_ pose: PoseResult) -> [FeedbackItem] {
        var items: [FeedbackItem] = []
        for joint in criticalJoints {
            let lm = pose.landmark(joint.type)
            if (lm?.confidence ?? 0) < jointVisibilityThreshold {
                items.append(FeedbackItem(
                    layer: .jointVisibility,
                    message: "Move your \(joint.label) into view",
                    isRequired: false
                ))
            }
        }
        return items
    }

    // MARK: - Layer 4: Exercise Rules

    private func checkExerciseRules(_ pose: PoseResult) -> [FeedbackItem] {
        var items: [FeedbackItem] = []

        // Hip sag detection: if hips are significantly lower than the shoulder-ankle line
        if let hipSag = detectHipSag(pose) {
            items.append(hipSag)
        }

        // Shoulder asymmetry during descent
        if let asymmetry = detectShoulderAsymmetry(pose) {
            items.append(asymmetry)
        }

        if let knee = detectKneePushupStance(pose) {
            items.append(knee)
        }

        return items
    }

    /// Interior angle at `vertex` in degrees (0…180).
    private func vertexAngleDegrees(pA: CGPoint, vertex: CGPoint, pB: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: pA.x - vertex.x, y: pA.y - vertex.y)
        let v2 = CGPoint(x: pB.x - vertex.x, y: pB.y - vertex.y)
        let d1 = hypot(v1.x, v1.y)
        let d2 = hypot(v2.x, v2.y)
        guard d1 > 1e-5, d2 > 1e-5 else { return 180 }
        let dot = (v1.x * v2.x + v1.y * v2.y) / (d1 * d2)
        return acos(min(1, max(-1, dot))) * 180 / .pi
    }

    /// Suggests full plank when knees are strongly bent (common on modified push-ups; needs hip/knee/ankle, e.g. MediaPipe).
    private func detectKneePushupStance(_ pose: PoseResult) -> FeedbackItem? {
        let chains: [(LandmarkType, LandmarkType, LandmarkType)] = [
            (.leftHip, .leftKnee, .leftAnkle),
            (.rightHip, .rightKnee, .rightAnkle),
        ]
        var bestMin: CGFloat = 180
        var sawLeg = false
        for (hi, kn, an) in chains {
            guard let h = pose.landmark(hi), let k = pose.landmark(kn), let a = pose.landmark(an),
                  h.confidence > 0.25, k.confidence > 0.25, a.confidence > 0.25 else { continue }
            sawLeg = true
            let ang = vertexAngleDegrees(pA: h.position, vertex: k.position, pB: a.position)
            bestMin = min(bestMin, ang)
        }
        guard sawLeg else {
            kneeBentFrames = max(0, kneeBentFrames - 1)
            return nil
        }

        if bestMin < 130 {
            kneeBentFrames += 1
        } else {
            kneeBentFrames = max(0, kneeBentFrames - 1)
        }

        if kneeBentFrames >= kneeBentFrameThreshold {
            return FeedbackItem(
                layer: .exerciseRule,
                message: "Lift your knees — straighten into a full plank",
                isRequired: false
            )
        }
        return nil
    }

    private func detectHipSag(_ pose: PoseResult) -> FeedbackItem? {
        guard let ls = pose.landmark(.leftShoulder), let rs = pose.landmark(.rightShoulder),
              let lh = pose.landmark(.leftHip), let rh = pose.landmark(.rightHip),
              ls.confidence > 0.3 && rs.confidence > 0.3 &&
              lh.confidence > 0.3 && rh.confidence > 0.3 else {
            hipSagFrames = max(0, hipSagFrames - 1)
            return nil
        }

        let shoulderMidY = (ls.position.y + rs.position.y) / 2
        let hipMidY = (lh.position.y + rh.position.y) / 2

        // In top-left origin (y-down), hips higher = smaller y = good plank.
        // Hips sagging = hipMidY much larger than shoulderMidY.
        // Use world coords if available for more accurate check.
        var isSagging = false
        if let wls = pose.worldLandmark(.leftShoulder), let wrs = pose.worldLandmark(.rightShoulder),
           let wlh = pose.worldLandmark(.leftHip), let wrh = pose.worldLandmark(.rightHip) {
            let shoulderMidWorld = (wls.position.y + wrs.position.y) / 2
            let hipMidWorld = (wlh.position.y + wrh.position.y) / 2
            isSagging = (hipMidWorld - shoulderMidWorld) > 0.06
        } else {
            isSagging = (hipMidY - shoulderMidY) > 0.08
        }

        if isSagging {
            hipSagFrames += 1
        } else {
            hipSagFrames = max(0, hipSagFrames - 1)
        }

        if hipSagFrames >= hipSagFrameThreshold {
            return FeedbackItem(layer: .exerciseRule, message: "Keep your hips level — don't let them sag", isRequired: false)
        }
        return nil
    }

    private func detectShoulderAsymmetry(_ pose: PoseResult) -> FeedbackItem? {
        guard let ls = pose.landmark(.leftShoulder), let rs = pose.landmark(.rightShoulder),
              ls.confidence > 0.3 && rs.confidence > 0.3 else { return nil }

        let yDiff: CGFloat
        if let wls = pose.worldLandmark(.leftShoulder), let wrs = pose.worldLandmark(.rightShoulder) {
            yDiff = abs(CGFloat(wls.position.y - wrs.position.y))
        } else {
            yDiff = abs(ls.position.y - rs.position.y)
        }

        if yDiff > 0.07 {
            return FeedbackItem(layer: .exerciseRule, message: "Keep your shoulders level", isRequired: false)
        }
        return nil
    }
}
