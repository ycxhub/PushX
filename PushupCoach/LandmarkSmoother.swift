import CoreGraphics

/// Exponential moving average per joint to reduce jitter from raw Vision output.
final class LandmarkSmoother {
    private var smoothed: [LandmarkType: CGPoint] = [:]
    /// Higher = more responsive, lower = smoother (0…1).
    private let alpha: CGFloat

    init(alpha: CGFloat = 0.28) {
        self.alpha = alpha
    }

    func smooth(landmarks: [Landmark]) -> [Landmark] {
        landmarks.map { lm in
            guard lm.confidence > 0.15 else {
                smoothed.removeValue(forKey: lm.type)
                return lm
            }
            if let prev = smoothed[lm.type] {
                let nx = alpha * lm.position.x + (1 - alpha) * prev.x
                let ny = alpha * lm.position.y + (1 - alpha) * prev.y
                let p = CGPoint(x: nx, y: ny)
                smoothed[lm.type] = p
                return Landmark(type: lm.type, position: p, confidence: lm.confidence)
            } else {
                smoothed[lm.type] = lm.position
                return lm
            }
        }
    }

    func reset() {
        smoothed.removeAll()
    }
}
