import CoreGraphics

/// Shared normalized-space thresholds for pose gate, calibration, feedback, and coaching UI.
enum PushupPoseConstants {
    /// Inset from each edge of the frame for the “whole body in the box” check and safe-frame overlay.
    static let safeFrameInset: CGFloat = 0.015

    // MARK: Shoulder span — gate vs calibration (arm’s-length / phone on floor)

    /// Looser band so users can lock tracking without standing very far back.
    static let shoulderSpanGateMin: CGFloat = 0.035
    static let shoulderSpanGateMax: CGFloat = 0.92

    /// Slightly stricter band for calibration / rep arming (reduces junk poses).
    static let shoulderSpanCalibrateMin: CGFloat = 0.05
    static let shoulderSpanCalibrateMax: CGFloat = 0.86

    /// Wider "usable" band for diagnostics and late-start recovery when the subject is visible but not ideal.
    static let shoulderSpanUsableMin: CGFloat = 0.028
    static let shoulderSpanUsableMax: CGFloat = 0.96

    /// Arm hint for **calibration** (`isCalibratedForPushup`).
    static let armHintConfidenceCalibration: Float = 0.2

    /// Softer arm hint for **checklist dots** (plank often drops elbow confidence).
    static let armHintConfidenceChecklist: Float = 0.14

    /// Degrees from vertical; trunk heuristic (retained for analytics, not used for plank gating).
    static let minTrunkAngleForPushup: CGFloat = 34

    /// Landmark overlay — dots.
    static let overlayMinConfidenceDot: Float = 0.55

    /// Skeleton lines (slightly looser so edges stay visible in motion).
    static let overlayMinConfidenceLine: Float = 0.45
}
