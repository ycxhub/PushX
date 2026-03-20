import CoreGraphics

/// Shared normalized-space thresholds for pose gate, calibration, feedback, and coaching UI.
enum PushupPoseConstants {
    /// Inset from each edge of the frame for the “whole body in the box” check and safe-frame overlay.
    static let safeFrameInset: CGFloat = 0.05

    // MARK: Shoulder span — gate vs calibration (arm’s-length / phone on floor)

    /// Looser band so users can lock tracking without standing very far back.
    static let shoulderSpanGateMin: CGFloat = 0.042
    static let shoulderSpanGateMax: CGFloat = 0.88

    /// Slightly stricter band for calibration / rep arming (reduces junk poses).
    static let shoulderSpanCalibrateMin: CGFloat = 0.055
    static let shoulderSpanCalibrateMax: CGFloat = 0.82

    /// Arm hint for **calibration** (`isCalibratedForPushup`).
    static let armHintConfidenceCalibration: Float = 0.2

    /// Softer arm hint for **checklist dots** (plank often drops elbow confidence).
    static let armHintConfidenceChecklist: Float = 0.14

    /// Degrees from vertical; trunk heuristic (side-on); face-on uses `isPlankLikeForFaceOnCamera`.
    static let minTrunkAngleForPushup: CGFloat = 40

    /// Landmark overlay — dots.
    static let overlayMinConfidenceDot: Float = 0.55

    /// Skeleton lines (slightly looser so edges stay visible in motion).
    static let overlayMinConfidenceLine: Float = 0.45
}
